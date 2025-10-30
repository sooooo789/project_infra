#!/bin/bash
set -eux

apt-get update -y
apt-get install -y python3-pip python3-venv

python3 -m venv /opt/appenv
/opt/appenv/bin/pip install --upgrade pip
/opt/appenv/bin/pip install streamlit pandas plotly boto3

mkdir -p /opt/app
cat >/opt/app/app.py <<'PY'
import streamlit as st
st.set_page_config(page_title="gj-lab", layout="wide")
st.title("gj-lab: Streamlit on EC2")
st.write("Health check: /_stcore/health")
PY
chown -R ubuntu:ubuntu /opt/app

cat >/etc/systemd/system/streamlit.service <<'SVC'
[Unit]
Description=Streamlit App
After=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/app
ExecStart=/opt/appenv/bin/streamlit run app.py --server.address 0.0.0.0 --server.port 8080
Restart=always

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable --now streamlit