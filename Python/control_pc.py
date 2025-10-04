#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# control_pc.py
# Controle remoto seguro do SEU PC via SSH
# NÃO usar em computadores que você não tem autorização

import paramiko
import getpass

# Dados do PC
host = input("IP do PC: ")
user = input("Usuário no PC: ")
port = 22
password = getpass.getpass("Senha: ")  # não mostra na tela

# Cria cliente SSH
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

try:
    ssh.connect(hostname=host, port=port, username=user, password=password)
    print("[✔] Conectado ao PC!")
except paramiko.AuthenticationException:
    print("[✖] Falha de autenticação. Verifique usuário/senha.")
    exit(1)
except Exception as e:
    print(f"[✖] Erro de conexão: {e}")
    exit(1)

# Loop de comandos
while True:
    cmd = input(f"{user}@{host}> ").strip()
    if cmd.lower() in ['exit', 'quit', 'sair']:
        break
    if not cmd:
        continue
    stdin, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode()
    err = stderr.read().decode()
    if out:
        print(out)
    if err:
        print(err)

ssh.close()
print("[*] Conexão encerrada.")
