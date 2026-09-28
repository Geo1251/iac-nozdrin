# --- Ключ сервисного аккаунта (хранится вне репозитория) ---
mkdir -p ~/.yc-keys
if [ ! -s ~/.yc-keys/nozdrin-03-key.json ]; then
  yc iam key create --service-account-name nozdrin-03-sa \
    --output ~/.yc-keys/nozdrin-03-key.json
fi

