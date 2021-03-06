##
## Build ILA models and their SystemC simulator
##
FROM ubuntu:bionic as ilabuilder
LABEL stage=intermediate

# var
ENV WORK_ROOT /root
ENV VIRTUAL_ENV 3laEnv
ENV BUILD_PREF $WORK_ROOT/$VIRTUAL_ENV
RUN mkdir -p $BUILD_PREF

# required packages
RUN apt update && DEBIAN_FRONTEND=noninteractive apt install --yes --no-install-recommends \
    bison \
    build-essential \
    ca-certificates \
    flex \
    gcc-5 \
    g++-5 \
    git \
    libz3-dev \
    openssh-client \
    python3 \
    python3-pip \
    wget \
    z3 \
    && rm -rf /var/lib/apt/lists/*

# setup local build via virtualenv
WORKDIR $WORK_ROOT
RUN pip3 install virtualenv
RUN virtualenv $VIRTUAL_ENV

# cmake
ENV CMAKE_DIR $WORK_ROOT/cmake-3.19.2-Linux-x86_64
WORKDIR $WORK_ROOT
RUN wget https://github.com/Kitware/CMake/releases/download/v3.19.2/cmake-3.19.2-Linux-x86_64.tar.gz
RUN tar zxvf cmake-3.19.2-Linux-x86_64.tar.gz

# SystemC
ENV SYSC_DIR $WORK_ROOT/systemc-2.3.3
WORKDIR $WORK_ROOT
RUN wget https://accellera.org/images/downloads/standards/systemc/systemc-2.3.3.tar.gz
RUN tar zxvf systemc-2.3.3.tar.gz
WORKDIR $SYSC_DIR
RUN mkdir -p build
WORKDIR $SYSC_DIR/build
RUN $CMAKE_DIR/bin/cmake $SYSC_DIR -DCMAKE_INSTALL_PREFIX=$BUILD_PREF -DCMAKE_CXX_STANDARD=11 && \
    make -j"$(nproc)" && \
    make install 

# to access private repo
ARG SSH_KEY
RUN eval "$(ssh-agent -s)"
RUN mkdir -p /root/.ssh/ && \
    echo "$SSH_KEY" > /root/.ssh/id_rsa && \
    chmod -R 600 /root/.ssh/ && \
    ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

# 3la_sim_testbench
ENV SIM_TEST_DIR $WORK_ROOT/3la_sim_testbench
WORKDIR $WORK_ROOT
RUN git clone --depth=1 git@github.com:LeeOHzzZ/3la_sim_testbench.git $SIM_TEST_DIR

# ILAng
ENV ILANG_DIR $WORK_ROOT/ILAng
WORKDIR $WORK_ROOT
ADD https://api.github.com/repos/PrincetonUniveristy/ILAng/git/refs/heads/master ilang_version.json
RUN git clone --depth=1 https://github.com/PrincetonUniversity/ILAng.git $ILANG_DIR
WORKDIR $ILANG_DIR
RUN mkdir -p build 
WORKDIR $ILANG_DIR/build
RUN $CMAKE_DIR/bin/cmake $ILANG_DIR -DCMAKE_INSTALL_PREFIX=$BUILD_PREF && \
    make -j"$(nproc)" && \
    make install 

# vta-ila
ENV VTA_ILA_DIR $WORK_ROOT/vta-ila
WORKDIR $WORK_ROOT
ADD https://api.github.com/repos/LeeOHzzZ/vta-ila/git/refs/heads/master vtaila_version.json
RUN git clone --depth=1 https://github.com/LeeOHzzZ/vta-ila.git $VTA_ILA_DIR
WORKDIR $VTA_ILA_DIR
RUN mkdir -p build
WORKDIR $VTA_ILA_DIR/build
RUN $CMAKE_DIR/bin/cmake $VTA_ILA_DIR -DCMAKE_PREFIX_PATH=$BUILD_PREF && \
    make -j"$(nproc)" && \
    ./vta

# vta-ila simulator
ENV VTA_SIM_DIR $VTA_ILA_DIR/build/sim_model
RUN cp $SIM_TEST_DIR/vta/sim_driver.cc $VTA_SIM_DIR/app/main.cc
RUN cp $SIM_TEST_DIR/vta/uninterpreted_func.cc $VTA_SIM_DIR/extern/uninterpreted_func.cc
WORKDIR $VTA_SIM_DIR
RUN mkdir -p build
WORKDIR $VTA_SIM_DIR/build
RUN HEADER="-isystem$SIM_TEST_DIR/vta/ap_include" && \
    $CMAKE_DIR/bin/cmake $VTA_SIM_DIR \
      -DCMAKE_PREFIX_PATH=$BUILD_PREF \
      -DCMAKE_CXX_FLAGS=$HEADER && \
    make -j"$(nproc)"

# FlexNLP
ENV FLEX_NLP_DIR $WORK_ROOT/FlexNLP
WORKDIR $WORK_ROOT
RUN git clone --depth=1 git@github.com:ttambe/FlexNLP.git $FLEX_NLP_DIR
WORKDIR $FLEX_NLP_DIR
RUN git submodule update --init --recursive

# flexnlp-ila
ENV FLEX_ILA_DIR $WORK_ROOT/flexnlp-ila
WORKDIR $WORK_ROOT
ADD https://api.github.com/repos/PrincetonUniversity/flexnlp-ila/git/refs/heads/master flexila_version.json
RUN git clone --depth=1 https://github.com/PrincetonUniversity/flexnlp-ila.git $FLEX_ILA_DIR
WORKDIR $FLEX_ILA_DIR
RUN mkdir -p build
WORKDIR $FLEX_ILA_DIR/build
RUN $CMAKE_DIR/bin/cmake $FLEX_ILA_DIR -DCMAKE_PREFIX_PATH=$BUILD_PREF && \
    make -j"$(nproc)" && \
    ./flex

# FlexNLP-ila simulator
ENV FLEX_SIM_DIR $FLEX_ILA_DIR/build/sim_model
RUN cp $SIM_TEST_DIR/flexnlp/sim_driver/sim_driver.cc $FLEX_SIM_DIR/app/main.cc
RUN cp $SIM_TEST_DIR/flexnlp/sim_driver/uninterpreted_func.cc $FLEX_SIM_DIR/extern/uninterpreted_func.cc
WORKDIR $FLEX_SIM_DIR
RUN mkdir -p build
WORKDIR $FLEX_SIM_DIR/build
RUN HEADER0="-isystem$SIM_TEST_DIR/ac_include" && \
    HEADER1="-isystem$FLEX_NLP_DIR/cmod/include" && \
    HEADER2="-isystem$FLEX_NLP_DIR/matchlib/cmod/include" && \
    HEADER3="-isystem$FLEX_NLP_DIR/matchlib/rapidjson/include" && \
    HEADER4="-isystem$FLEX_NLP_DIR/matchlib/connections/include" && \
    DEF0="-DSC_INCLUDE_DYNAMIC_PROCESSES" && \
    DEF1="-DCONNECTIONS_ACCURATE_SIM" && \
    DEF2="-DHLS_CATAPULT" && \
    $CMAKE_DIR/bin/cmake $FLEX_SIM_DIR \
      -DCMAKE_PREFIX_PATH=$BUILD_PREF \
      -DCMAKE_CXX_STANDARD=11 \
      -DCMAKE_CXX_COMPILER=g++-5 \
      -DCMAKE_CXX_FLAGS="$HEADER0 $HEADER1 $HEADER2 $HEADER3 $HEADER4 $DEF0 $DEF1 $DEF2" && \
    make -j"$(nproc)"

##
## Build TVM/BYOC
##
FROM ubuntu:bionic as tvmbuilder
LABEL stage=intermediate

# var
ENV WORK_ROOT /root
ENV VIRTUAL_ENV 3laEnv
ENV BUILD_PREF $WORK_ROOT/$VIRTUAL_ENV
RUN mkdir -p $BUILD_PREF

# required packages
RUN apt update && DEBIAN_FRONTEND=noninteractive apt install --yes --no-install-recommends \
    ca-certificates \
    openssh-client \
    git \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    libtinfo-dev \
    zlib1g-dev \
    build-essential \
    cmake \
    libedit-dev \
    libxml2-dev \
    llvm \
    llvm-dev \
    clang \
    && rm -rf /var/lib/apt/lists/*

# setup local build via virtualenv
WORKDIR $WORK_ROOT
RUN pip3 install virtualenv
RUN virtualenv $VIRTUAL_ENV
RUN $BUILD_PREF/bin/pip3 install numpy decorator attrs scipy pytest

# to access private repo
ARG SSH_KEY
RUN eval "$(ssh-agent -s)"
RUN mkdir -p /root/.ssh/ && \
    echo "$SSH_KEY" > /root/.ssh/id_rsa && \
    chmod -R 600 /root/.ssh/ && \
    ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

# 3la-tvm
ENV TVM_DIR $WORK_ROOT/3la-tvm
WORKDIR $WORK_ROOT
RUN git clone git@github.com:Bo-Yuan-Huang/3la-tvm.git $TVM_DIR
WORKDIR $TVM_DIR
RUN git submodule init && \
    git submodule update
RUN mkdir -p build && \
    cp cmake/config.cmake build && \
    echo "set(USE_LLVM llvm-config)" >> build/config.cmake
WORKDIR $TVM_DIR/build
RUN cmake $TVM_DIR -DUSE_ILAVTA_CODEGEN=ON -DUSE_ILAFLEX_CODEGEN=ON && \
    make -j"$(nproc)"

##
## Deployment
##
FROM ubuntu:bionic

RUN apt update && DEBIAN_FRONTEND=noninteractive apt install --yes --no-install-recommends \
    python3 \
    python3-pip \
    libtinfo-dev \
    zlib1g-dev \
    libedit-dev \
    libxml2-dev \
    llvm \
    llvm-dev \
    clang \
    && rm -rf /var/lib/apt/lists/*

# setup env
ENV VIRTUAL_ENV 3laEnv
ENV BUILD_PREF /root/$VIRTUAL_ENV
ENV TVM_DIR /root/3la-tvm
COPY --from=ilabuilder $BUILD_PREF $BUILD_PREF
COPY --from=tvmbuilder $BUILD_PREF $BUILD_PREF
COPY --from=tvmbuilder $TVM_DIR $TVM_DIR

# fetch ILA simulator
COPY --from=ilabuilder /root/vta-ila/build/sim_model/build/vta $BUILD_PREF/bin/vta_ila_sim
COPY --from=ilabuilder /root/flexnlp-ila/build/sim_model/build/flex $BUILD_PREF/bin/flexnlp_ila_sim

# fetch example testbench
ENV EXM_PROG /root/testbench
RUN mkdir -p $EXM_PROG
COPY --from=ilabuilder /root/3la_sim_testbench/vta/prog_frag $EXM_PROG/vta
COPY --from=ilabuilder /root/3la_sim_testbench/flexnlp/sim_driver/prog_frag $EXM_PROG/flexnlp

# init
WORKDIR /root
RUN echo "source /root/$VIRTUAL_ENV/bin/activate" >> init.sh
RUN echo "export PYTHONPATH=$TVM_DIR/python:${PYTHONPATH}" >> init.sh
CMD echo "run 'source init.sh' to start" && /bin/bash
