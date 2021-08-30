## Docker Swarm Management for TooCoolCats.com/Coupons

### Deploy a stack

```
docker stack deploy [OPTIONS] STACK
``` 

```
eg: docker stack deploy --with-registry-auth -c proxy-stack.yml blog_
```

```
noted: blog_ is a unique PREFIX, and set by you
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
