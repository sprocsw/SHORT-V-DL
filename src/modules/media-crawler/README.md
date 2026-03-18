# media-crawler

## 职责
核心爬虫逻辑模块，封装了原 `MediaCrawler` 项目的支持各平台的数据抓取脚本集合。

## 文件
| File | Purpose |
|------|---------|
| `main.py` | 核心调度入口 |
| `config/` | 爬虫配置文件 |
| `tools/` | 各种实用工具与爬虫核心基类 |

## 依赖
参考原项目的 `requirements.txt`。

## 使用
可以通过内部 `web-api` 经过 `sys.path` 引入该目录的方法来调用相关组件，或独立运行：
```bash
cd src/modules/media-crawler
python main.py
```
