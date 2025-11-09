FROM 486205206788.dkr.ecr.us-east-1.amazonaws.com/multiarch/task15:nginx-base-1.0
COPY ./html/index.html /usr/share/nginx/html/index.html
