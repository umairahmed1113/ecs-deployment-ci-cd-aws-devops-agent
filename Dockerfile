FROM nginx:1.27-alpine
 
# Remove default Nginx placeholder page
RUN rm -rf /usr/share/nginx/html/*
 
# Copy your entire project into Nginx's web root
# Expected structure:
#   index.html
#   css/
#     style.css
#     responsive.css
#   js/
#     script.js
#   img/
#     mountain.png
#     mountain_dark.jpg
#     menu-btn.png
#     apple-touch-icon.png
#     favicon-32x32.png
#     favicon-16x16.png
#     GitHub120px.png
#     img1.jfif
#     img2.jfif
#     img3.png  img4.png  img5.png  img6.png
#     carousel-img4.jpg  carousel-img5.jpg  carousel-img6.jpg
#   site.webmanifest
COPY . /usr/share/nginx/html
 
# Custom Nginx config — adds gzip, correct MIME types,
# cache headers, and a clean 404 fallback
RUN printf 'server {\n\
    listen       80;\n\
    server_name  _;\n\
    root         /usr/share/nginx/html;\n\
    index        index.html;\n\
\n\
    # Gzip static assets\n\
    gzip on;\n\
    gzip_types text/plain text/css application/javascript image/svg+xml;\n\
    gzip_min_length 1024;\n\
\n\
    # Cache images / fonts aggressively\n\
    location ~* \.(png|jpg|jfif|jpeg|gif|ico|webp|woff2?|ttf|eot|svg)$ {\n\
        expires 30d;\n\
        add_header Cache-Control "public, immutable";\n\
    }\n\
\n\
    # Cache CSS & JS for 1 day\n\
    location ~* \.(css|js)$ {\n\
        expires 1d;\n\
        add_header Cache-Control "public";\n\
    }\n\
\n\
    # Serve index.html for any unmatched path (SPA-safe)\n\
    location / {\n\
        try_files $uri $uri/ /index.html;\n\
    }\n\
\n\
    # Custom 404\n\
    error_page 404 /index.html;\n\
}\n' > /etc/nginx/conf.d/default.conf
 
# Nginx listens on port 80
EXPOSE 80
 
# Nginx runs in foreground (required for Docker / ECS)
CMD ["nginx", "-g", "daemon off;"]
 
