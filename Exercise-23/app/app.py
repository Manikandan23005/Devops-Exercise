import os
from flask import Flask, jsonify

app = Flask(__name__)

APP_PASSWORD = os.getenv("APP_PASSWORD", "default_safe_password_321")

@app.route("/")
def home():
    env = os.getenv("APP_ENV", "production")
    
    if env.lower() == "prod" or env.lower() == "production":
        gradient = "linear-gradient(135deg, #111827 0%, #1f2937 100%)"
        theme_color = "#3b82f6"
    else:
        gradient = "linear-gradient(135deg, #1e3a8a 0%, #3b82f6 100%)"
        theme_color = "#60a5fa"

    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Troubleshooting Lab - {env.upper()}</title>
        <style>
            body {{
                font-family: 'Inter', sans-serif;
                background: {gradient};
                color:
                display: flex;
                justify-content: center;
                align-items: center;
                height: 100vh;
                margin: 0;
            }}
            .card {{
                background: rgba(255, 255, 255, 0.05);
                backdrop-filter: blur(16px);
                -webkit-backdrop-filter: blur(16px);
                border-radius: 24px;
                padding: 40px;
                box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.5);
                border: 1px solid rgba(255, 255, 255, 0.1);
                text-align: center;
                max-width: 500px;
                width: 100%;
                transition: transform 0.3s ease;
            }}
            .card:hover {{
                transform: translateY(-8px);
            }}
            h1 {{
                font-size: 2.2rem;
                margin-bottom: 8px;
                background: linear-gradient(to right,
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
            }}
            .badge {{
                background-color: {theme_color};
                color:
                padding: 6px 16px;
                border-radius: 9999px;
                font-weight: 700;
                font-size: 0.85rem;
                display: inline-block;
                margin-bottom: 24px;
                text-transform: uppercase;
                letter-spacing: 0.05em;
            }}
            .desc {{
                color:
                font-size: 1.1rem;
                line-height: 1.6;
            }}
            .footer {{
                margin-top: 32px;
                font-size: 0.8rem;
                color:
                border-top: 1px solid rgba(255, 255, 255, 0.1);
                padding-top: 20px;
            }}
        </style>
    </head>
    <body>
        <div class="card">
            <div class="badge">{env} environment</div>
            <h1>CI/CD Troubleshooting Lab</h1>
            <p class="desc">If you can see this page, the pipeline is green and the application has deployed successfully via GitOps!</p>
            <div class="footer">Exercise 23 - DevOps Pipeline Troubleshooting</div>
        </div>
    </body>
    </html>
    """
    return html

@app.route("/healthz")
def healthz():
    return jsonify({"status": "healthy"})

if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
