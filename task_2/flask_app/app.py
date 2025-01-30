from flask import Flask, render_template
import os

app = Flask(__name__)

@app.route('/')
def home():
    docker_message = os.getenv('DOCKER_ENV', 'Default message from Container')
    tf_message = os.getenv('TF_ENV', 'Default message from Container')

    return render_template('index.html', docker_message=docker_message, tf_message=tf_message)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)