import { useState, useEffect } from 'react'
import { Download, RefreshCw, Layers, AlertCircle, Trash2, Globe, XCircle } from 'lucide-react'

// Backend API URL
const API_BASE = 'http://localhost:8081/api'

export default function DouyinDownload() {
  const [text, setText] = useState('')
  const [cookie, setCookie] = useState('')
  const [cookieStatus, setCookieStatus] = useState('Cookie not saved.')
  const [status, setStatus] = useState('Waiting for input...')
  const [summary, setSummary] = useState('No items parsed.')
  const [items, setItems] = useState<any[]>([])
  const [showCookie, setShowCookie] = useState(false)

  const CACHE_KEY = 'douyin_cookie_cache'
  const CACHE_TS = 'douyin_cookie_cache_ts'

  useEffect(() => {
    // 初始化时读取缓存
    const cached = localStorage.getItem(CACHE_KEY)
    if (cached) {
      setCookie(cached)
      setCookieStatus('已加载缓存的 Cookie。')
    }
  }, [])

  // 监听 cookie 状态变化并自动保存
  const handleCookieChange = (val: string) => {
    setCookie(val)
    if (val.trim()) {
      localStorage.setItem(CACHE_KEY, val.trim())
      localStorage.setItem(CACHE_TS, Date.now().toString())
      setCookieStatus('Cookie 已自动保存。')
    } else {
      localStorage.removeItem(CACHE_KEY)
      setCookieStatus('Cookie 已清除。')
    }
  }

  const openAndPollCookie = async () => {
    setCookieStatus('正在拉起登录浏览器...')
    try {
      const res = await fetch(`${API_BASE}/douyin/login/open`, { method: 'POST' })
      if (!res.ok) {
        throw new Error('打开浏览器失败')
      }
      
      setCookieStatus('浏览器已打开，请在弹出的浏览器中扫码或输入账号登录。等待自动提取 Cookie...')
      
      // 开始轮询读取 Cookie
      let attempts = 0
      const poll = setInterval(async () => {
        attempts++
        if (attempts > 60) { // 3分钟超时
          clearInterval(poll)
          setCookieStatus('获取 Cookie 超时，请重试。')
          return
        }
        
        try {
          const cookieRes = await fetch(`${API_BASE}/douyin/login/cookie`)
          if (cookieRes.ok) {
            const data = await cookieRes.json()
            // 简单通过是否包含 sessionid 来判断抖音是否通过了登录验证
            if (data.cookie && data.cookie.includes('sessionid=')) {
              clearInterval(poll)
              setCookieStatus('检测到登录状态，正在完成最终 Cookie 捕获...')
              // 延迟 2.5 秒，确保所有鉴权 Cookie (如 ttwid, passport_csrf_token 等) 完整落盘
              setTimeout(async () => {
                try {
                  const finalRes = await fetch(`${API_BASE}/douyin/login/cookie`)
                  if (finalRes.ok) {
                    const finalData = await finalRes.json()
                    handleCookieChange(finalData.cookie)
                    setCookieStatus('✅ 登录/获取Cookie成功！您可以继续保持浏览器打开，或手动关闭它。')
                  }
                } catch (e) {}
              }, 2500)
            }
          }
        } catch (e) {
          // 忽略轮询时的网络错误
        }
      }, 3000)

    } catch (err: any) {
      setCookieStatus(err.message || '操作失败')
    }
  }

  const closeLoginBrowser = async () => {
    try {
      await fetch(`${API_BASE}/douyin/login/close`, { method: 'POST' })
      setCookieStatus('已发送关闭浏览器请求。')
    } catch (e) {}
  }

  const extractItemsFromInput = (raw: string) => {
    const candidates: string[] = []
    const urlMatches = raw.match(/https?:\/\/[^\s]+/g) || []
    urlMatches.forEach(v => candidates.push(v))
    const hostMatches = raw.match(/(v\.douyin\.com\/[a-zA-Z0-9_\-]+\/?|(?:www\.)?douyin\.com\/[^\s]+|iesdouyin\.com\/[^\s]+)/g) || []
    hostMatches.forEach(v => candidates.push(v.startsWith('http') ? v : `https://${v}`))
    const idMatches = raw.match(/\b\d{15,}\b/g) || []
    idMatches.forEach(v => candidates.push(v))
    
    // Deduplicate
    const result = Array.from(new Set(candidates.map(v => v.replace(/["'”’），。！!？?)\\]}>]+$/g, '').trim()))).filter(Boolean)
    if (result.length === 0 && raw.trim()) result.push(raw.trim())
    return result
  }

  const parseAll = async () => {
    const inputs = extractItemsFromInput(text)
    if (inputs.length === 0) {
      setStatus('Please paste Douyin share text or links.')
      return
    }

    const initItems = inputs.map(input => ({
      input, extracted_url: '', resolved_url: '', aweme_id: '', status: 'parsing', error: ''
    }))
    setItems(initItems)
    setStatus(`Parsing ${inputs.length} items...`)

    let readyCount = 0
    let errCount = 0

    const newItems = [...initItems]
    for (let i = 0; i < inputs.length; i++) {
      try {
        const res = await fetch(`${API_BASE}/douyin/parse`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ text: inputs[i] })
        })
        const data = await res.json()
        if (!res.ok) throw new Error(data.detail || 'Parse failed')
        
        newItems[i] = { 
          ...newItems[i], 
          extracted_url: data.extracted_url, 
          resolved_url: data.resolved_url, 
          aweme_id: data.aweme_id,
          status: 'ready' 
        }
        readyCount++
      } catch (err: any) {
        newItems[i] = { ...newItems[i], status: 'error', error: err.message }
        errCount++
      }
      setItems([...newItems])
      setSummary(`${inputs.length} items · ${readyCount} ready · ${errCount} failed`)
    }
    setStatus('Parsing completed.')
  }

  const downloadItem = async (index: number) => {
    const item = items[index]
    if (item.status === 'parsing' || item.status === 'downloading' || item.status === 'error') return

    const newItems = [...items]
    newItems[index].status = 'downloading'
    setItems(newItems)

    try {
      const res = await fetch(`${API_BASE}/douyin/download`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ aweme_id: item.aweme_id, cookie: cookie })
      })
      if (!res.ok) {
        const detail = await res.json()
        throw new Error(detail.detail || 'Download failed')
      }
      
      const blob = await res.blob()
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `${item.aweme_id}.mp4`
      a.click()
      URL.revokeObjectURL(url)

      newItems[index] = { ...newItems[index], status: 'downloaded' }
    } catch (err: any) {
      newItems[index] = { ...newItems[index], status: 'error', error: err.message }
    }
    setItems([...newItems])
  }

  const downloadAll = async () => {
    setStatus('Downloading items...')
    for (let i = 0; i < items.length; i++) {
        if (items[i].status === 'ready' || items[i].status === 'downloaded') {
            await downloadItem(i)
            await new Promise(r => setTimeout(r, 600)) // Rate limit protection
        }
    }
    setStatus('All downloads completed.')
  }

  const retryItem = async (index: number) => {
    const item = items[index]
    if (item.aweme_id) {
        // 重试下载
        await downloadItem(index)
    } else {
        // 重试解析
        const newItems = [...items]
        newItems[index] = { ...item, status: 'parsing', error: '' }
        setItems(newItems)
        try {
          const res = await fetch(`${API_BASE}/douyin/parse`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text: item.input })
          })
          const data = await res.json()
          if (!res.ok) throw new Error(data.detail || 'Parse failed')
          
          setItems(prevItems => {
            const updated = [...prevItems]
            updated[index] = {
              ...updated[index],
              extracted_url: data.extracted_url,
              resolved_url: data.resolved_url,
              aweme_id: data.aweme_id,
              status: 'ready'
            }
            return updated
          })
        } catch (err: any) {
          setItems(prevItems => {
            const updated = [...prevItems]
            updated[index] = { ...updated[index], status: 'error', error: err.message }
            return updated
          })
        }
    }
  }

  return (
    <div style={{ width: '100%', maxWidth: '960px', margin: '0 auto', padding: '2rem', fontFamily: 'system-ui, sans-serif', boxSizing: 'border-box', textAlign: 'left' }}>
      <div style={{ padding: '24px', background: 'linear-gradient(135deg, rgba(50, 216, 199, 0.16), rgba(255, 92, 154, 0.1))', borderRadius: '16px', marginBottom: '24px' }}>
        <h1 style={{ margin: '0 0 10px 0', fontSize: '28px', color: '#fff' }}>抖音视频批量下载器</h1>
        <p style={{ margin: 0, color: '#9aa4b2' }}>复制任何形式的抖音分享文案、链接，支持批量解析与无水印下载。</p>
      </div>

      <div style={{ background: '#121826', padding: '24px', borderRadius: '16px', marginBottom: '24px', border: '1px solid rgba(255,255,255,0.08)' }}>
        <label style={{ display: 'block', fontSize: '13px', color: '#9aa4b2', marginBottom: '8px', textTransform: 'uppercase' }}>分享文案 / 链接 (可填入多行)</label>
        <textarea
          style={{ width: '100%', boxSizing: 'border-box', resize: 'vertical', minHeight: '120px', background: '#0e1320', color: '#fff', border: '1px solid rgba(255,255,255,0.08)', borderRadius: '12px', padding: '16px', marginBottom: '16px', fontFamily: 'monospace' }}
          value={text}
          onChange={e => setText(e.target.value)}
          placeholder="例如: 2.89 DHV:/ d@n.QK 07/06 ... https://v.douyin.com/JFGj57FxDHg/ ..."
        />

        <label style={{ display: 'block', fontSize: '13px', color: '#9aa4b2', marginBottom: '8px', textTransform: 'uppercase' }}>抖音 Cookie (选填，防封号建议填写)</label>
        {cookie && !showCookie ? (
          <button 
            onClick={() => setShowCookie(true)} 
            style={{ width: '100%', padding: '16px', background: 'rgba(50, 216, 199, 0.1)', color: '#32d8c7', border: '1px solid rgba(50, 216, 199, 0.3)', borderRadius: '12px', marginBottom: '16px', cursor: 'pointer', fontWeight: 'bold' }}>
            ✅ 已成功获取 Cookie，受保护隐藏中。点击查看或修改
          </button>
        ) : (
          <div style={{ position: 'relative' }}>
            <textarea
              style={{ width: '100%', boxSizing: 'border-box', resize: 'vertical', minHeight: '60px', background: '#0e1320', color: '#fff', border: '1px solid rgba(255,255,255,0.08)', borderRadius: '12px', padding: '16px', marginBottom: '16px', fontFamily: 'monospace' }}
              value={cookie}
              onChange={e => handleCookieChange(e.target.value)}
              placeholder="填入您的 Douyin cookie"
            />
            {cookie && (
              <button 
                onClick={() => setShowCookie(false)} 
                style={{ position: 'absolute', top: '10px', right: '10px', background: '#2a334b', color: '#fff', border: 'none', padding: '4px 10px', borderRadius: '6px', fontSize: '12px', cursor: 'pointer' }}>
                隐藏
              </button>
            )}
          </div>
        )}

        <div style={{ display: 'flex', gap: '10px', alignItems: 'center', flexWrap: 'wrap', marginBottom: '24px' }}>
          <button onClick={openAndPollCookie} style={btnStyleSecondary}><Globe size={14} /> 拉起扫码登录 (自动获取 Cookie)</button>
          <button onClick={closeLoginBrowser} style={btnStyleSecondary}><XCircle size={14} /> 关闭后台浏览器</button>
          <span style={{ fontSize: '13px', color: '#9aa4b2' }}>{cookieStatus}</span>
        </div>

        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
          <button onClick={parseAll} style={btnStylePrimary}><RefreshCw size={16} /> 全部解析 (Parse All)</button>
          <button 
            onClick={downloadAll} 
            disabled={items.filter(i => i.status === 'ready' || i.status === 'downloaded').length === 0} 
            style={items.filter(i => i.status === 'ready' || i.status === 'downloaded').length === 0 ? btnStyleDisabled : btnStylePrimary}>
            <Download size={16} /> 下载全部
          </button>
          <button onClick={() => { setItems([]); setText(''); setStatus('Waiting for input...'); setSummary('No items parsed.') }} style={btnStyleSecondary}>
            <Trash2 size={16} /> 清空
          </button>
        </div>
        <div style={{ marginTop: '16px', fontSize: '13px', color: '#9aa4b2' }}>{status}</div>
      </div>

      <div style={{ background: '#121826', padding: '24px', borderRadius: '16px', border: '1px solid rgba(255,255,255,0.08)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
          <h2 style={{ fontSize: '18px', margin: 0, color: '#fff', display: 'flex', alignItems: 'center', gap: '8px' }}><Layers size={20} /> 解析结果</h2>
          <span style={{ fontSize: '13px', color: '#9aa4b2' }}>{summary}</span>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          {items.map((item, idx) => (
            <div key={idx} style={{ background: '#0e1320', padding: '16px', borderRadius: '12px', border: '1px solid rgba(255,255,255,0.08)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '12px' }}>
                <span style={{ fontSize: '12px', color: '#9aa4b2', textTransform: 'uppercase' }}>Item {idx + 1}</span>
                <span style={{ ...statusBadgeStyle, background: item.status === 'ready' || item.status === 'downloaded' ? 'rgba(50, 216, 199, 0.2)' : item.status === 'error' ? 'rgba(255, 92, 154, 0.2)' : 'rgba(94, 161, 255, 0.2)', color: item.status === 'ready' || item.status === 'downloaded' ? '#32d8c7' : item.status === 'error' ? '#ff5c9a' : '#5ea1ff' }}>
                  {item.status.toUpperCase()}
                </span>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', fontSize: '13px', fontFamily: 'monospace', color: '#ccc' }}>
                {item.extracted_url ? (
                    <div><span style={{ color: '#9aa4b2', marginRight: '8px' }}>URL:</span><a href={item.extracted_url} target="_blank" style={{ color: '#32d8c7', wordBreak: 'break-all' }}>{item.extracted_url}</a></div>
                ) : (
                    <div><span style={{ color: '#9aa4b2', marginRight: '8px' }}>INPUT:</span><span style={{ wordBreak: 'break-all' }}>{item.input || '-'}</span></div>
                )}
                {item.error && <div style={{ color: '#ff5c9a', display: 'flex', alignItems: 'center', gap: '4px' }}><AlertCircle size={14} /> {item.error}</div>}
              </div>
              <div style={{ marginTop: '12px', display: 'flex', gap: '8px' }}>
                {item.status === 'error' && (
                  <button 
                    onClick={() => retryItem(idx)} 
                    style={btnStyleSecondarySmall}>
                    <RefreshCw size={12} />
                    {item.aweme_id ? '重新下载' : '重新解析'}
                  </button>
                )}
                <button 
                  onClick={() => downloadItem(idx)} 
                  disabled={item.status === 'parsing' || item.status === 'downloading' || item.status === 'error' || !item.aweme_id} 
                  style={(item.status === 'parsing' || item.status === 'downloading' || item.status === 'error' || !item.aweme_id) ? btnStyleDisabledSmall : btnStyleSecondarySmall}>
                  下载该项
                </button>
              </div>
            </div>
          ))}
          {items.length === 0 && <div style={{ color: '#9aa4b2', fontSize: '13px' }}>暂无解析结果。</div>}
        </div>
      </div>
    </div>
  )
}

const btnStylePrimary = {
  display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 20px', 
  background: '#32d8c7', color: '#05121a', border: 'none', borderRadius: '99px',
  fontWeight: 'bold', cursor: 'pointer', fontSize: '14px'
}
const btnStyleSecondary = {
  display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 20px', 
  background: 'transparent', color: '#fff', border: '1px solid rgba(255,255,255,0.2)', borderRadius: '99px',
  fontWeight: 'bold', cursor: 'pointer', fontSize: '14px'
}
const btnStyleDisabled = {
  ...btnStylePrimary, background: 'rgba(255,255,255,0.1)', color: '#666', cursor: 'not-allowed'
}
const btnStyleDisabledSmall = {
  ...btnStyleDisabled, padding: '6px 12px', fontSize: '12px'
}
const btnStyleSecondarySmall = {
  ...btnStyleSecondary, padding: '6px 12px', fontSize: '12px'
}
const statusBadgeStyle = {
  fontSize: '11px', padding: '4px 8px', borderRadius: '99px', fontWeight: 'bold'
}
