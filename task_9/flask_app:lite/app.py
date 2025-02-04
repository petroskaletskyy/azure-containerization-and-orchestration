from flask import Flask, render_template
import os
import socket
import requests

app = Flask(__name__)

def get_public_ip():
    # Get public IP address
    try:
        response = requests.get('https://api64.ipify.org?format=text', timeout=5)
        return response.text
    except requests.RequestException:
        return 'Unable to retrieve'

@app.route('/')
def home():
    # Get the hostname of the container
    container_name = os.getenv('CONTAINER_NAME', socket.gethostname())

    # Get local IP address
    local_ip_address = socket.gethostbyname(socket.gethostname())

    # Get public IP address
    ip_address = get_public_ip()

    return render_template('index.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)