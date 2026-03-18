import { Routes, Route, Link } from 'react-router-dom'
import DouyinDownload from './pages/DouyinDownload'
import './App.css'

function Home() {
  return (
    <div className="home-container" style={{ padding: '2rem', textAlign: 'center' }}>
      <h1>SHORT-V-DL 控制台</h1>
      <p>欢迎使用新版 MediaCrawler 交互系统</p>
      <div style={{ marginTop: '2rem' }}>
        <Link to="/douyin-download" style={{ padding: '10px 20px', backgroundColor: '#646cff', color: 'white', borderRadius: '8px', textDecoration: 'none' }}>
          前往 抖音下载 (Douyin Download) 测试页
        </Link>
      </div>
    </div>
  )
}

function App() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="/douyin-download" element={<DouyinDownload />} />
    </Routes>
  )
}

export default App
