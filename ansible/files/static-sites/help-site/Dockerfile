# help-site (ShopStack Help, Docusaurus) — served as static HTML by nginx.
# Same pattern as docs-site: the pre-built Docusaurus output is synced to build/html/
# by setup-static-sites.yml, then copied into the nginx image.
FROM nginx:alpine
COPY html/ /usr/share/nginx/html
EXPOSE 80
