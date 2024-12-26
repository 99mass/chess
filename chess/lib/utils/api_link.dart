const apiLink='http://10.0.2.2:8081/users/';
const socketLink='ws://10.0.2.2:8081/ws';
// pour les emulations sur telephone, il faut utiliser l'adresse IP de l'ordinateur
// qui heberge l'application, et non pas l'adresse IP 10.0.2.2 qui est une adresse
// IP specifique pour l'emulation sur ordinateur.
// Pour trouver l'adresse IP de l'ordinateur, vous pouvez utiliser la commande
// ifconfig dans le terminal de votre ordinateur.
// Par exemple, si l'adresse IP de votre ordinateur est 192.168.1.25, vous devrez
// remplacer les lignes ci-dessus par :
// const apiLink='http://192.168.1.25:8081/users/';
// const socketLink='ws://192.168.1.25:8081/ws';
