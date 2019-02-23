@mkdir build
@cd build
@mkdir imports
@g++ -std=c++14 -I%CS_DEV_PATH%\include -I..\include -shared -static -fPIC -s -O3 ..\network.cpp -L%CS_DEV_PATH%\lib -lcovscript -lws2_32 -lwsock32 -o .\imports\network.cse