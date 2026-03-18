# -*- coding: utf-8 -*-
# Copyright (c) 2025 relakkes@gmail.com
#
# This file is part of MediaCrawler project.
# Repository: https://github.com/NanmiCoder/MediaCrawler/blob/main/api/routers/douyin.py
# GitHub: https://github.com/NanmiCoder
# Licensed under NON-COMMERCIAL LEARNING LICENSE 1.1
#
# 声明：本代码仅供学习和研究目的使用。使用者应遵守以下原则：
# 1. 不得用于任何商业用途。
# 2. 使用时应遵守目标平台的使用条款和robots.txt规则。
# 3. 不得进行大规模爬取或对平台造成运营干扰。
# 4. 应合理控制请求频率，避免给目标平台带来不必要的负担。
# 5. 不得用于任何非法或不当的用途。
#
# 详细许可条款请参阅项目根目录下的LICENSE文件。
# 使用本代码即表示您同意遵守上述原则和LICENSE中的所有条款。

import asyncio
import os
import re
import secrets
import urllib.parse
from contextlib import suppress
from typing import Optional, Tuple

import httpx
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from playwright.async_api import async_playwright, BrowserContext, Page, Playwright

import config
from media_platform.douyin.help import get_a_bogus_from_js, get_web_id, parse_video_info_from_url
from store.douyin import _extract_video_download_url
from tools.crawler_util import convert_cookies, extract_url_params_to_dict, get_user_agent

router = APIRouter(prefix="/douyin", tags=["douyin"])

_URL_RE = re.compile(r"(https?://[^\s]+)")
_URL_TRIM = "\"'”’），。！!？?)\\]}>"
_DOUYIN_HOST_RE = re.compile(r"(v\.douyin\.com/[A-Za-z0-9]+/?|(?:www\.)?douyin\.com/[^\s]+|iesdouyin\.com/[^\s]+)")

_login_lock = asyncio.Lock()
_login_playwright: Optional[Playwright] = None
_login_context: Optional[BrowserContext] = None
_login_page: Optional[Page] = None


def _is_context_closed(context: Optional[BrowserContext]) -> bool:
    if context is None:
        return True
    is_closed_attr = getattr(context, "is_closed", None)
    try:
        if callable(is_closed_attr):
            return bool(is_closed_attr())
        if isinstance(is_closed_attr, bool):
            return is_closed_attr
    except Exception:
        return True
    try:
        _ = context.pages
    except Exception:
        return True
    return False


def _is_page_closed(page: Optional[Page]) -> bool:
    if page is None:
        return True
    is_closed_attr = getattr(page, "is_closed", None)
    try:
        if callable(is_closed_attr):
            return bool(is_closed_attr())
        if isinstance(is_closed_attr, bool):
            return is_closed_attr
    except Exception:
        return True
    try:
        _ = page.url
    except Exception:
        return True
    return False


async def _reset_login_refs(close_context: bool = False) -> None:
    global _login_context, _login_page
    if close_context and _login_context is not None:
        with suppress(Exception):
            await _login_context.close()
    _login_page = None
    _login_context = None


class DouyinParseRequest(BaseModel):
    text: str


class DouyinDownloadRequest(BaseModel):
    text: Optional[str] = None
    url: Optional[str] = None
    aweme_id: Optional[str] = None
    cookie: Optional[str] = None


def _extract_first_url(text: str) -> str:
    if not text:
        return ""
    match = _URL_RE.search(text)
    if match:
        return match.group(1).rstrip(_URL_TRIM)
    host_match = _DOUYIN_HOST_RE.search(text)
    if host_match:
        url = host_match.group(1).rstrip(_URL_TRIM)
        if not url.startswith("http"):
            url = "https://" + url
        return url
    return ""


def _cookie_str_to_dict(cookie: str) -> dict:
    cookie_dict = {}
    if not cookie:
        return cookie_dict
    for item in cookie.split(";"):
        if "=" not in item:
            continue
        key, value = item.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key:
            cookie_dict[key] = value
    return cookie_dict


def _extract_ms_token(cookie: str) -> str:
    cookie_dict = _cookie_str_to_dict(cookie)
    return cookie_dict.get("msToken", "")


async def _resolve_short_url(url: str) -> str:
    async with httpx.AsyncClient(follow_redirects=False, timeout=10) as client:
        try:
            resp = await client.get(url)
        except httpx.HTTPError:
            return ""
    if resp.status_code in {301, 302, 303, 307, 308}:
        return resp.headers.get("Location", "")
    if resp.status_code == 200:
        return url
    return ""


def _get_douyin_user_data_dir() -> str:
    return os.path.join(os.getcwd(), "browser_data", config.USER_DATA_DIR % "dy")


async def _ensure_login_context() -> Tuple[BrowserContext, Page]:
    global _login_playwright, _login_context, _login_page

    async with _login_lock:
        if _login_context is not None:
            try:
                # Probe context liveness: stale contexts can still expose attributes
                # but fail when issuing commands (e.g. new_page/cookies).
                await _login_context.cookies()
                if _is_page_closed(_login_page):
                    _login_page = _login_context.pages[0] if _login_context.pages else await _login_context.new_page()
                await _login_page.goto("https://www.douyin.com", wait_until="domcontentloaded")
                return _login_context, _login_page
            except Exception:
                await _reset_login_refs(close_context=True)

        if _login_playwright is None:
            _login_playwright = await async_playwright().start()

        user_data_dir = _get_douyin_user_data_dir()
        os.makedirs(user_data_dir, exist_ok=True)

        try:
            _login_context = await _login_playwright.chromium.launch_persistent_context(
                user_data_dir=user_data_dir,
                headless=False,
                accept_downloads=False,
                viewport={"width": 1280, "height": 900},
                channel="chrome",
            )
        except Exception:
            _login_context = await _login_playwright.chromium.launch_persistent_context(
                user_data_dir=user_data_dir,
                headless=False,
                accept_downloads=False,
                viewport={"width": 1280, "height": 900},
            )

        try:
            _login_page = _login_context.pages[0] if _login_context.pages else await _login_context.new_page()
            await _login_page.goto("https://www.douyin.com", wait_until="domcontentloaded")
        except Exception:
            await _reset_login_refs(close_context=True)
            raise

        return _login_context, _login_page


async def _read_login_state() -> Tuple[str, str]:
    global _login_playwright
    cookie_str = ""
    ms_token = ""

    if _login_context is not None:
        try:
            cookie_str, _ = convert_cookies(await _login_context.cookies())
            if not _is_page_closed(_login_page):
                try:
                    ms_token = await _login_page.evaluate("() => window.localStorage.getItem('xmst')")
                except Exception:
                    ms_token = ""
            return cookie_str, ms_token
        except Exception:
            await _reset_login_refs(close_context=True)

    user_data_dir = _get_douyin_user_data_dir()
    if not os.path.exists(user_data_dir):
        return "", ""

    if _login_playwright is None:
        try:
            _login_playwright = await async_playwright().start()
        except Exception:
            return "", ""

    try:
        context = await _login_playwright.chromium.launch_persistent_context(
            user_data_dir=user_data_dir,
            headless=True,
            accept_downloads=False,
        )
    except Exception:
        return "", ""

    page = context.pages[0] if context.pages else await context.new_page()
    try:
        await page.goto("https://www.douyin.com", wait_until="domcontentloaded")
        cookie_str, _ = convert_cookies(await context.cookies())
        try:
            ms_token = await page.evaluate("() => window.localStorage.getItem('xmst')")
        except Exception:
            ms_token = ""
    finally:
        await context.close()

    return cookie_str, ms_token

def _extract_aweme_id(url: str) -> Tuple[str, str]:
    try:
        info = parse_video_info_from_url(url)
        if info.aweme_id:
            return info.aweme_id, info.url_type
    except Exception:
        pass

    params = extract_url_params_to_dict(url)
    modal_id = params.get("modal_id")
    if modal_id:
        return modal_id, "modal"

    for pattern in (r"/video/(\d+)", r"/share/video/(\d+)"):
        match = re.search(pattern, url)
        if match:
            return match.group(1), "normal"

    return "", "unknown"


def _build_aweme_params(aweme_id: str, user_agent: str, ms_token: str = "") -> dict:
    params = {
        "device_platform": "webapp",
        "aid": "6383",
        "channel": "channel_pc_web",
        "version_code": "190600",
        "version_name": "19.6.0",
        "update_version_code": "170400",
        "pc_client_type": "1",
        "cookie_enabled": "true",
        "browser_language": "zh-CN",
        "browser_platform": "MacIntel",
        "browser_name": "Chrome",
        "browser_version": "125.0.0.0",
        "browser_online": "true",
        "engine_name": "Blink",
        "os_name": "Mac OS",
        "os_version": "10.15.7",
        "cpu_core_num": "8",
        "device_memory": "8",
        "engine_version": "109.0",
        "platform": "PC",
        "screen_width": "2560",
        "screen_height": "1440",
        "effective_type": "4g",
        "round_trip_time": "50",
        "webid": get_web_id(),
        "msToken": ms_token or secrets.token_urlsafe(64),
        "aweme_id": aweme_id,
    }
    query_string = urllib.parse.urlencode(params)
    params["a_bogus"] = get_a_bogus_from_js("/aweme/v1/web/aweme/detail/", query_string, user_agent)
    return params


async def _fetch_aweme_detail(aweme_id: str, cookie: str = "") -> dict:
    user_agent = get_user_agent()
    ms_token = _extract_ms_token(cookie)
    params = _build_aweme_params(aweme_id, user_agent, ms_token)
    headers = {
        "User-Agent": user_agent,
        "Referer": f"https://www.douyin.com/video/{aweme_id}",
        "Accept": "application/json",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    }
    cookies = _cookie_str_to_dict(cookie)
    async with httpx.AsyncClient(timeout=30, follow_redirects=True, headers=headers, cookies=cookies) as client:
        # Prime cookies (ttwid) to reduce anti-bot rejections.
        try:
            await client.get("https://www.douyin.com/")
        except httpx.HTTPError:
            pass

        resp = await client.get(
            "https://www.douyin.com/aweme/v1/web/aweme/detail/",
            params=params,
        )

    if resp.status_code != 200:
        snippet = resp.text[:200].replace("\n", " ").strip()
        raise HTTPException(
            status_code=502,
            detail=f"Douyin API error (status {resp.status_code}): {snippet}",
        )

    content_type = resp.headers.get("Content-Type", "")
    if "application/json" not in content_type.lower():
        snippet = resp.text[:200].replace("\n", " ").strip()
        raise HTTPException(
            status_code=502,
            detail=f"Douyin response is not JSON: {snippet or 'empty response'}",
        )

    try:
        data = resp.json()
    except ValueError:
        snippet = resp.text[:200].replace("\n", " ").strip()
        raise HTTPException(
            status_code=502,
            detail=f"Douyin response parse failed: {snippet or 'empty response'}",
        )

    return data.get("aweme_detail", {})


async def _parse_input(text: str) -> Tuple[str, str, str]:
    raw = (text or "").strip()
    if not raw:
        raise HTTPException(status_code=400, detail="Empty input")
    if raw.isdigit():
        return raw, "", ""

    extracted_url = _extract_first_url(raw) or raw
    if "douyin.com" not in extracted_url and "iesdouyin.com" not in extracted_url:
        raise HTTPException(status_code=400, detail="No Douyin URL found")

    resolved_url = extracted_url
    if "v.douyin.com" in extracted_url:
        resolved_url = await _resolve_short_url(extracted_url)
        if not resolved_url:
            raise HTTPException(status_code=400, detail="Failed to resolve short URL")

    aweme_id, _ = _extract_aweme_id(resolved_url)
    if not aweme_id:
        raise HTTPException(status_code=400, detail="Failed to parse aweme_id")

    return aweme_id, extracted_url, resolved_url


@router.post("/parse")
async def parse_douyin_link(request: DouyinParseRequest):
    aweme_id, extracted_url, resolved_url = await _parse_input(request.text)
    return {
        "input": request.text,
        "extracted_url": extracted_url,
        "resolved_url": resolved_url,
        "aweme_id": aweme_id,
        "detail_url": f"https://www.douyin.com/video/{aweme_id}",
    }


@router.post("/login/open")
async def open_douyin_login():
    """打开抖音登录页（Playwright 持久化上下文）"""
    timeout_seconds = max(int(getattr(config, "BROWSER_LAUNCH_TIMEOUT", 60)), 5)
    try:
        await asyncio.wait_for(_ensure_login_context(), timeout=timeout_seconds)
    except asyncio.TimeoutError as exc:
        raise HTTPException(status_code=504, detail=f"Open login browser timeout ({timeout_seconds}s)") from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Open login browser failed: {exc}") from exc
    return {"status": "opened"}


@router.get("/login/cookie")
async def get_douyin_login_cookie():
    """从 Playwright 登录态读取 Cookie 和 msToken"""
    cookie_str, ms_token = await _read_login_state()
    if not cookie_str:
        raise HTTPException(status_code=404, detail="Login state not found")
    return {"cookie": cookie_str, "ms_token": ms_token or ""}


@router.post("/login/close")
async def close_douyin_login():
    """关闭登录浏览器上下文"""
    global _login_context, _login_page
    if not _is_page_closed(_login_page):
        try:
            await _login_page.close()
        except Exception:
            pass
    if not _is_context_closed(_login_context):
        try:
            await _login_context.close()
        except Exception:
            pass
    _login_page = None
    _login_context = None
    return {"status": "closed"}


async def _download_response(
    aweme_id: str,
    extracted_url: str = "",
    resolved_url: str = "",
    cookie: str = "",
) -> StreamingResponse:
    aweme_detail = await _fetch_aweme_detail(aweme_id, cookie)
    video_url = _extract_video_download_url(aweme_detail)
    if not video_url:
        raise HTTPException(status_code=404, detail="Video URL not found")

    cookies = _cookie_str_to_dict(cookie)

    async def stream_video():
        headers = {
            "User-Agent": get_user_agent(),
            "Referer": f"https://www.douyin.com/video/{aweme_id}",
        }
        async with httpx.AsyncClient(timeout=None, follow_redirects=True, headers=headers, cookies=cookies) as client:
            async with client.stream("GET", video_url) as resp:
                resp.raise_for_status()
                async for chunk in resp.aiter_bytes():
                    yield chunk

    filename = f"{aweme_id}.mp4"
    response_headers = {
        "Content-Disposition": f'attachment; filename="{filename}"'
    }
    if extracted_url or resolved_url:
        response_headers["X-Source-Url"] = extracted_url or resolved_url

    return StreamingResponse(stream_video(), media_type="video/mp4", headers=response_headers)


@router.get("/download")
async def download_video(
    text: Optional[str] = Query(default=None),
    url: Optional[str] = Query(default=None),
    aweme_id: Optional[str] = Query(default=None),
):
    if aweme_id:
        parsed_id = aweme_id.strip()
        extracted_url = ""
        resolved_url = ""
    else:
        source_text = text or url
        if not source_text:
            raise HTTPException(status_code=400, detail="Missing aweme_id or text/url")
        parsed_id, extracted_url, resolved_url = await _parse_input(source_text)
        aweme_id = parsed_id

    return await _download_response(aweme_id, extracted_url, resolved_url, "")


@router.post("/download")
async def download_video_post(request: DouyinDownloadRequest):
    if request.aweme_id:
        parsed_id = request.aweme_id.strip()
        extracted_url = ""
        resolved_url = ""
    else:
        source_text = request.text or request.url
        if not source_text:
            raise HTTPException(status_code=400, detail="Missing aweme_id or text/url")
        parsed_id, extracted_url, resolved_url = await _parse_input(source_text)
    return await _download_response(parsed_id, extracted_url, resolved_url, request.cookie or "")
