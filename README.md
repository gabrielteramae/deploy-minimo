# Deploy mínimo — rsync e nginx

![nginx](https://img.shields.io/badge/nginx-1.27-009639?style=flat&logo=nginx&logoColor=white)
![rsync](https://img.shields.io/badge/rsync-deploy-555555?style=flat)
![Docker](https://img.shields.io/badge/Docker-compose-2496ED?style=flat&logo=docker&logoColor=white)

Publicar um site estático sem GitHub Pages e sem Vercel. São duas peças: o nginx entrega a pasta, o rsync manda essa pasta para o servidor.

| Peça | O que faz aqui |
| --- | --- |
| nginx | Serve `site/` na porta 80, com gzip e cache curto de CSS |
| rsync | Copia `site/` para o destino e apaga o que saiu do diretório (`--delete`) |
| Docker | Sobe o mesmo `default.conf` na máquina local, sem VPS |
| SSH | Só no envio remoto. A chave fica fora deste repositório |

Não emite certificado, não cria usuário no servidor e não abre a porta 80 por você.

## Stack

- nginx 1.27 (imagem Alpine no Compose, ou o pacote da distro no servidor)
- rsync e OpenSSH no cliente
- HTML e CSS, sem build

## Estrutura

```
deploy-minimo/
├── site/                 index.html e styles.css
├── nginx/default.conf    server block. O mesmo arquivo vai para o servidor
├── scripts/deploy.sh     rsync local ou user@host:path
├── docker-compose.yml    prova o nginx em 127.0.0.1:8088
└── README.md
```

## Como rodar

Pré-requisito local: Docker. No envio remoto: rsync, SSH e um nginx já instalado.

```bash
git clone https://github.com/gabrielteramae/deploy-minimo.git
cd deploy-minimo
docker compose up
```

Abre em `http://127.0.0.1:8088/`. Pare com `docker compose down`.

Cópia local, sem rede, para ver o que o rsync faria:

```bash
scripts/deploy.sh --local /tmp/deploy-minimo-site --dry-run
scripts/deploy.sh --local /tmp/deploy-minimo-site
```

Envio para um servidor. `DEPLOY_PATH` precisa existir e ser gravável pelo usuário.

```bash
DEPLOY_HOST=exemplo.com \
DEPLOY_USER=deploy \
DEPLOY_PATH=/var/www/deploy-minimo \
DEPLOY_RELOAD=1 \
scripts/deploy.sh
```

`--dry-run` lista o diff e não grava. `DEPLOY_RELOAD=1` só vale sem `--dry-run`: no host roda `sudo nginx -t` e `systemctl reload nginx`.

No servidor, uma vez:

```bash
sudo mkdir -p /var/www/deploy-minimo
sudo chown deploy:deploy /var/www/deploy-minimo
sudo cp nginx/default.conf /etc/nginx/conf.d/deploy-minimo.conf
```

Ajuste o `root` desse conf para `/var/www/deploy-minimo` antes de copiar. No Compose o root continua `/usr/share/nginx/html`, que é o volume de `site/`.

HTTPS fica de fora de propósito. O passo seguinte, se o domínio já aponta para a máquina, é o Certbot no próprio nginx. Não faz parte deste mínimo.

---

© 2026 Gabriel Teramae Chan
