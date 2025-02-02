from flask import Flask, render_template
import os
import socket
import requests
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient

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

    key_vault_name = os.getenv('KEY_VAULT_NAME')
    secret_name = os.getenv('SECRET_NAME')

    credential = ManagedIdentityCredential()
    vault_url = f"https://{key_vault_name}.vault.azure.net"

    client = SecretClient(vault_url, credential)
    retrieved_secret = client.get_secret(secret_name)

    print(f"Retrieved secret: {retrieved_secret.value}")

    return render_template('index.html', container_name=container_name, local_ip_address=local_ip_address, ip_address=ip_address, retrieved_secret=retrieved_secret.value)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)