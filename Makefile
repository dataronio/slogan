all:
	make -C ./src SLOGAN_ROOT=`pwd`

install:
	make -C ./src install SLOGAN_ROOT=`pwd`

uninstall:
	make -C ./src uninstall SLOGAN_ROOT=`pwd`

clean:
	make -C ./src clean SLOGAN_ROOT=`pwd`
