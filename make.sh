mkdir build
cd build
mkdir imports
g++ -std=c++11 -I ../include -shared -fPIC -s -O3 ../network.cpp -o ./imports/network.cse