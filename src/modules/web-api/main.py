import os
import sys
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# 将 crawler 核心库加入系统路径
CRAWLER_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "media-crawler")
sys.path.append(CRAWLER_DIR)

from api.routers import crawler_router, data_router, douyin_router, websocket_router

app = FastAPI(
    title="SHORT-V-DL Web API",
    description="Web service wrapper for MediaCrawler tasks",
    version="1.0.0"
)

# CORS 配置，允许前端端口 8080 等访问
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:8080",
        "http://localhost:5173",
        "http://127.0.0.1:8080",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册原项目的相关路由
app.include_router(crawler_router, prefix="/api")
app.include_router(data_router, prefix="/api")
app.include_router(douyin_router, prefix="/api")
app.include_router(websocket_router, prefix="/api")

@app.get("/")
def read_root():
    return {"status": "ok", "message": "SHORT-V-DL API is running on 8081."}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8081, reload=True)
