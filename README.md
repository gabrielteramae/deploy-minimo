# Deploy mínimo — rsync e nginx

![nginx](https://img.shields.io/badge/nginx-1.27-009639?style=flat&logo=nginx&logoColor=white)
![rsync](https://img.shields.io/badge/rsync-deploy-555555?style=flat)
![Docker](https://img.shields.io/badge/Docker-compose-2496ED?style=flat&logo=docker&logoColor=white)

Publicar um site estático sem GitHub Pages e sem Vercel. O nginx entrega um symlink. O rsync grava um release novo e só então troca esse symlink.

| Peça | O que faz aqui |
| --- | --- |
| nginx | Serve `/var/www/deploy-minimo/current` na porta 80, com gzip e cache curto de CSS |
| rsync | Copia `site/` para `releases/<stamp>/`. O `--delete` vale só dentro desse release |
| symlink | `current` aponta para o release. Se o reload falhar, volta para o anterior |
| Docker | Sobe o mesmo `default.conf` na máquina local, sem VPS |
| SSH | Só no envio remoto. A chave fica fora deste repositório |

Não cria usuário no servidor e não abre a porta 80 por você. HTTPS é um exemplo à parte, em `nginx/tls.conf`, para quando já existir domínio.

## Stack

- nginx 1.27 (imagem Alpine no Compose, ou o pacote da distro no servidor)
- rsync e OpenSSH no cliente
- HTML e CSS, sem build

## Estrutura

```
deploy-minimo/
├── site/                 index.html e styles.css
├── nginx/default.conf    HTTP. root .../current
├── nginx/tls.conf        exemplo de 443 e redirect. Não entra no Compose
├── scripts/deploy.sh     rsync local ou user@host
├── scripts/activate.sh   troca o symlink, confere o root, recarrega ou volta
├── scripts/check.sh      recusa caminho perigoso, testa release e rollback
├── docker-compose.yml    prova o nginx em 127.0.0.1:8088
└── .github/workflows/    check no push
```

No servidor o layout fica assim:

```
/var/www/deploy-minimo/
├── releases/20261027.../   cópia completa de site/
└── current -> releases/20261027...
```

São guardados os cinco releases mais novos. O ao vivo nunca é apagado com `--delete`.

## Como rodar

Pré-requisito local: Docker. No envio remoto: rsync, SSH e um nginx já instalado.

```bash
git clone https://github.com/gabrielteramae/deploy-minimo.git
cd deploy-minimo
docker compose up
```

Abre em `http://127.0.0.1:8088/`. Pare com `docker compose down`.

Cópia local, sem rede:

```bash
scripts/deploy.sh --local /tmp/deploy-minimo-site --dry-run
scripts/deploy.sh --local /tmp/deploy-minimo-site
```

`--dry-run` não cria pasta. Se `current` já existe, lista o diff contra ele.

Envio para um servidor. `DEPLOY_PATH` é a pasta pai (`releases/` e `current`), não o release.

```bash
DEPLOY_HOST=exemplo.com \
DEPLOY_USER=deploy \
DEPLOY_PATH=/var/www/deploy-minimo \
DEPLOY_RELOAD=1 \
scripts/deploy.sh
```

`DEPLOY_RELOAD=1` só vale sem `--dry-run`. No host, antes de trocar o symlink, o script lê `sudo nginx -T` e falha se nenhum `root` for exatamente `/var/www/deploy-minimo/current`. Aí troca `current` e roda `sudo nginx -t && sudo systemctl reload nginx`. Se o reload falhar, `current` volta para o release anterior.

O usuário `deploy` precisa de sudo sem senha só para esses três comandos. No servidor, uma vez:

```bash
sudo tee /etc/sudoers.d/deploy-minimo >/dev/null <<'EOF'
deploy ALL=(root) NOPASSWD: /usr/sbin/nginx -t, /usr/sbin/nginx -T, /bin/systemctl reload nginx
EOF
sudo chmod 440 /etc/sudoers.d/deploy-minimo
sudo visudo -cf /etc/sudoers.d/deploy-minimo
```

O caminho do `nginx` e do `systemctl` muda por distro. Ajuste a linha para o que `command -v nginx` e `command -v systemctl` mostrarem. O script chama `sudo nginx` e `sudo systemctl`, então o sudoers tem de bater com esses binários.

No servidor, uma vez, pasta e conf:

```bash
sudo mkdir -p /var/www/deploy-minimo
sudo chown deploy:deploy /var/www/deploy-minimo
sudo cp nginx/default.conf /etc/nginx/conf.d/deploy-minimo.conf
sudo nginx -t && sudo systemctl reload nginx
```

Se essa pasta ainda for o layout antigo (o `index.html` solto, servido como `root` direto), não misture. Mova a pasta, crie de novo e troque o conf para `root .../current` antes do primeiro envio com este script. `current` tem de ser symlink; o script recusa se for diretório.

O Compose monta `site/` em `/var/www/deploy-minimo/current`, o mesmo `root` do conf. O script recusa destino curto demais (`/`, `/var/www`, `/tmp`) para um engano não virar a pasta de releases.

## HTTPS

Fora do caminho do rsync. Com o domínio apontando para a máquina:

```bash
sudo certbot --nginx -d exemplo.com
```

O plugin do Certbot reescreve o nginx e emite o certificado em `/etc/letsencrypt/`. `nginx/tls.conf` é o formato esperado: porta 80 redireciona para 443, e o `root` continua `.../current`. Não commite `fullchain.pem` nem `privkey.pem`. Não carregue `tls.conf` junto com `default.conf` se os dois escutarem a porta 80 com o mesmo nome.

---

© 2026 Gabriel Teramae Chan
