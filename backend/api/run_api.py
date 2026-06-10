"""
Ponto de entrada para rodar a API.
Execute: python run_api.py
"""
import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "gauswoodsquote.main:app",
        host="0.0.0.0",
        port=8080,
        reload=True,
        log_level="info",
    )
