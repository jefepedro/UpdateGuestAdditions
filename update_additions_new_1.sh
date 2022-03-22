#!/bin/bash
# Autor: Dima

debug=0 # 0 para modo de operación, 1 para modo debug

cd="/dev/cdrom" # ruta de dispositivo óptico por defecto
vboxsf="vboxsf" # grupo de usuarios que pueden leer carpetas compartidas
cleanupfolder=0 # si se crea una carpeta temporal, indica que hay que borrarla
cleanupmnt=0 # si se crea un punto de montaje temporal, indica que hay que borrarlo

timeout=5 # segundos de cuenta atrás antes de reiniciar

# La función mostrará estado de ejecución de un comando 
# $1 = comando a ejecutar
# $2 = texto a mostrar
function procesar()
{
    ejec="$1"
    texto="$2"

    # si estamos en modo debug, nos imprime por la pantalla el comando a ejecutar
    if [ $debug -ne 0 ]; then echo \$ejec="$ejec"; fi

    # Imprimimos por la pantalla el texto de ejecución, tipo "Ejecutando..."
    echo -n "${texto}..."
    
    # con eval intentamos ejecutar el comando. Usamos eval para casos cuando el comando lleva tubería
    if eval "$ejec"; then
        # si la ejecución ha sido correcta, reemplazamos el mensaje anterior por otro, tipo "Ejecutando [ OK ]"
        echo -e "\r${texto} [ $(tput setaf 2)OK$(tput sgr0) ]" 
        # la función devuelve 0
        return 0
    else
        err="$?"
        # si la ejecución ha resultado en error, reemplazamos el mensaje de ejecución por "Ejecutando [ ERROR ]"
        echo -e "\r${texto} [ $(tput setaf 1)ERROR $err$(tput sgr0) ]" 
        # devolvemos el código de error producido al hilo de ejecución principal.
        return $err
    fi
}

# solicita permisos de sudo al usuario. 
sudo -p 'Por favor, introduce tu clave de usuario: ' echo -ne '\r'

# intenta obtener la lista de actualizaciones
procesar "sudo apt-get update -qq" "Buscando actualizaciones de Linux"

# intenta instalar las dependencias necesarias para el funcionamiento completo de Guest Additions
procesar "sudo apt-get install build-essential dkms linux-headers-$(uname -r) -yqq" "Instalando dependencias"

# el condicional intenta averiguar si existe ya un punto de montaje en uso para el dispositivo óptico
if procesar "mount | grep -q '/dev/$(readlink $cd)'" "Buscando dispositivo óptico"; then
    # si el dispositivo óptico ya está montado, obtiene su punto de montaje y nos avisa
    ga=$(mount | grep "/dev/$(readlink $cd)" | cut -f 3 -d" "| head -n 1)
    echo "Encontrado un dispositivo óptico en $ga"
else
    # si no está montado
    ga="/mnt/cdrom"
    if [[ ! -f /mnt/cdrom ]]; then
        # ya que carpeta para montaje no existe, la va a crear
        procesar "sudo mkdir -p $ga" "Creando carpeta $ga"
        # establecemos cleanupfolder=1 para indicar que debemos borrar esa carpeta posteriormente
        cleanupfolder=1
    fi
    

    if procesar "sudo mount -o ro $cd $ga" "Intentando montar $cd en $ga"; then 
        # si el montaje manual ha sido satisfactorio, indica que hay que desmontarlo después con cleanupmnt=1
        cleanupmnt=1
    else
        # en caso de que el montaje falla, no se puede proceder con la instalación, saliendo con el código de error 1
        echo "No ha sido posible montar $cd en $ga, saliendo"
        exit 1
    fi
    
fi

if [[ ! -f $ga/VBoxLinuxAdditions.run ]]; then
    # si el contenido de la unidad óptica no corresponde a un disco de Guest Additions, no se puede instalar
    echo "Guest Additions no se encuentran en $ga/VBoxLinuxAdditions.run, saliendo"
    # saliendo con el código de error 2
    exit 2
else
    echo "Instalando $ga/VBoxLinuxAdditions.run"
    # procedemos a la instalación. Este paso solo se ejecuta si no estamos en modo debug
    if [ $debug -eq 0 ]; then sudo sh $ga/VBoxLinuxAdditions.run --nox11; fi
fi

# si se ha montado la unidad manualmente
if [ $cleanupmnt -eq 1 ]; then
    # desmontando la unidad montada anteriormente
    procesar "sudo umount $ga" "Desmontando unidad $ga"
fi

# si se ha creado la carpeta temporal
if [ $cleanupfolder -eq 1 ]; then
    # borrando la carpeta temporal
    procesar "sudo rm -d $ga" "Borrando la carpeta $ga"
fi

# para acceder a carpetas compartidas, el usuario tiene que pertenecer al grupo vboxsf, comprobamos ese hecho
if ! procesar "id -nGz $USER | grep -qzxF '$vboxsf'" "Comprobando la pertenencia al grupo $vboxsf"; then
    # usuario actual no pertenece al grupo vboxsf, añadiendo.
    procesar "sudo usermod -aG vboxsf $USER" "Añadiendo usuario al grupo $vboxsf"
fi

# El instalador de Guest Additions recomienda reiniciar. Solicitamos acción al usuario.
read -p "Introduce Y para reiniciar: " -n 1 -r
echo    

# si el usuario pulsa y o Y en la pregunta anterior
if [[ $REPLY =~ ^[Yy]$ ]]
then
    for ((t="$timeout"; t>0; t--)); do
        # sacamos un mensaje con cuenta atrás
        echo -ne "\rReiniciando en $t segundos..."
        sleep 1
    done
    # reiniciando el equipo (este paso se omite en modo debug)
    if [ $debug -eq 0 ]; then sudo shutdown -r now; fi
    
else
    # el usuario ha decidido no reiniciar. Le avisamos de la recomendación de hacerlo.
    sleep 1
    echo "Recuerda reiniciar el equipo para que los cambios tengan efecto."
    sleep 3
fi