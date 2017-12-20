@mkdir build
@cd build
@mkdir imports
@g++ -std=c++11 -I ..\include -shared -static -fPIC -s -O3 ..\network.cpp -lws2_32 -lwsock32 -o .\imports\network.cse