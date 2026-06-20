#!/usr/bin/env python3
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

class SimpleHTTPRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Health check endpoint
        if self.path == '/healthz' or self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "healthy"}')
            return

        self.send_response(200)
        self.send_header('Content-type', 'text/html; charset=utf-8')
        self.end_headers()
        
        env = os.environ.get('APP_ENV', 'unknown')
        replica = os.environ.get('POD_NAME', 'unknown-pod')
        
        # Select gradient and details based on environment for high visual quality
        if env.lower() == 'prod' or env.lower() == 'production':
            gradient = "linear-gradient(135deg, #e53935 0%, #e35d5b 100%)" # Sleek Red
            badge_color = "#b71c1c"
        elif env.lower() == 'qa':
            gradient = "linear-gradient(135deg, #ff9800 0%, #f57c00 100%)" # Vibrant Orange
            badge_color = "#e65100"
        else:
            gradient = "linear-gradient(135deg, #1e3c72 0%, #2a5298 100%)" # Sleek Royal Blue for Dev
            badge_color = "#0d47a1"

        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>GitOps Python App - {env.upper()}</title>
            <style>
                body {{
                    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                    background: {gradient};
                    color: white;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    margin: 0;
                }}
                .card {{
                    background: rgba(255, 255, 255, 0.1);
                    backdrop-filter: blur(12px);
                    -webkit-backdrop-filter: blur(12px);
                    border-radius: 20px;
                    padding: 40px;
                    box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.3);
                    border: 1px solid rgba(255, 255, 255, 0.2);
                    text-align: center;
                    max-width: 500px;
                    width: 100%;
                    transition: transform 0.3s ease;
                }}
                .card:hover {{
                    transform: translateY(-5px);
                }}
                h1 {{
                    margin-top: 0;
                    font-size: 2.5em;
                    font-weight: 700;
                    letter-spacing: -0.5px;
                }}
                .badge {{
                    background-color: {badge_color};
                    padding: 8px 20px;
                    border-radius: 30px;
                    font-weight: 600;
                    display: inline-block;
                    margin-bottom: 25px;
                    text-transform: uppercase;
                    letter-spacing: 1px;
                    box-shadow: 0 4px 10px rgba(0,0,0,0.2);
                }}
                .info {{
                    font-size: 1.15em;
                    margin: 15px 0;
                    line-height: 1.5;
                }}
                .pod-name {{
                    font-family: 'Courier New', Courier, monospace;
                    background: rgba(0,0,0,0.2);
                    padding: 4px 8px;
                    border-radius: 4px;
                    font-weight: bold;
                }}
                .footer {{
                    margin-top: 35px;
                    font-size: 0.85em;
                    color: rgba(255, 255, 255, 0.7);
                    border-top: 1px solid rgba(255,255,255,0.15);
                    padding-top: 20px;
                }}
            </style>
        </head>
        <body>
            <div class="card">
                <div class="badge">{env.upper()} Environment</div>
                <h1>GitOps Python App</h1>
                <p class="info">Successfully deployed via <strong>ArgoCD</strong> using <strong>GitOps</strong>!</p>
                <p class="info"><strong>Pod Name:</strong> <span class="pod-name">{replica}</span></p>
                <div class="footer">Exercise 18 - DevOps Showcase</div>
            </div>
        </body>
        </html>
        """
        self.wfile.write(html.encode('utf-8'))

def run(server_class=HTTPServer, handler_class=SimpleHTTPRequestHandler, port=8080):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f"Starting server on port {port}...")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    print("Stopping server...")

if __name__ == '__main__':
    run()
