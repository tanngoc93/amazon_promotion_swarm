## Docker Swarm Management for TheDogPaws.com

### Deploy

```
docker stack deploy [OPTIONS] STACK
``` 

```
eg: docker stack deploy --with-registry-auth -c blog-stack.yml blog_
```

```html
Noted: blog_ is a unique PREFIX
```

### Show all of stacks

```
docker stack ls
```

### Show all of services

```
docker service ls
```

### Logging

```
docker service logs SERVICE_NAME
```
