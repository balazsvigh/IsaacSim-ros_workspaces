ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ENV ROS_DISTRO=jazzy
ENV ROS_ROOT=jazzy_ws
ENV ROS_PYTHON_VERSION=3
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /workspace

# ============================================================
# Base tools
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    cmake \
    build-essential \
    curl \
    wget \
    gnupg2 \
    lsb-release \
    software-properties-common \
    ca-certificates \
    locales && \
    locale-gen en_US en_US.UTF-8 && \
    update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 && \
    apt clean

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# ============================================================
# Python 3.11
# ============================================================
RUN add-apt-repository -y ppa:deadsnakes/ppa && \
    apt update && \
    apt install --no-install-recommends -y \
        python3.11 \
        python3.11-dev \
        python3.11-distutils \
        python3.11-venv && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    apt clean

RUN curl -s https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.11 get-pip.py --force-reinstall && \
    rm get-pip.py

# ============================================================
# ROS 2 apt source
# ============================================================
RUN wget https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc && \
    apt-key add ros.asc && \
    sh -c 'echo "deb [arch=$(dpkg --print-architecture)] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/ros2-latest.list'

# ============================================================
# System dependencies
# ============================================================
RUN apt update && apt install -y --no-install-recommends \
    pkg-config \
    cmake-extras \
    tmux \
    python3-yaml \
    python3-pip \
    python3-pytest-cov \
    python3-rosinstall-generator \
    python3-empy \
    ros-dev-tools \
    libpython3-dev \
    libeigen3-dev \
    libopencv-dev \
    python3-opencv \
    libssl-dev \
    liblttng-ust-dev \
    libasio-dev \
    libtinyxml2-dev \
    libcunit1-dev \
    libacl1-dev \
    libbullet-dev \
    libqhull-dev \
    libassimp-dev \
    liboctomap-dev \
    libconsole-bridge-dev \
    libfcl-dev \
    libyaml-cpp-dev \
    libfmt-dev \
    libpng-dev \
    libjpeg-dev \
    libzzip-dev \
    libx11-dev \
    libxaw7-dev \
    libxrandr-dev \
    libxcursor-dev \
    libxinerama-dev \
    libxi-dev \
    libxxf86vm-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    libglew-dev \
    libgles2-mesa-dev \
    libopengl-dev \
    libgl1-mesa-dri \
    libglx-mesa0 \
    freeglut3-dev \
    libfreetype-dev \
    libfreetype6-dev \
    libfontconfig1-dev \
    qtbase5-dev \
    qtchooser \
    qt5-qmake \
    qtbase5-dev-tools \
    libqt5core5a \
    libqt5gui5 \
    libqt5opengl5 \
    libqt5widgets5 \
    x11-apps \
    mesa-utils \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev && \
    apt clean

# ============================================================
# Python packages before Boost
# Keep this minimal, matching the working Humble pattern.
# ============================================================
RUN python3.11 -m pip install --upgrade pip setuptools==70.0.0
RUN python3.11 -m pip install empy==3.3.4 lark colcon-common-extensions

# ============================================================
# Boost 1.78 for Python 3.11
# ============================================================
RUN cd /workspace && \
    wget https://sourceforge.net/projects/boost/files/boost/1.78.0/boost_1_78_0.tar.bz2/download -O boost_1_78_0.tar.bz2 && \
    tar xf boost_1_78_0.tar.bz2 && \
    cd boost_1_78_0 && \
    ./bootstrap.sh --with-python=/usr/bin/python3.11 --prefix=/opt/boost_3_11 && \
    ./b2 install threading=multi variant=release link=shared python=3.11 && \
    cd .. && \
    rm -rf boost_1_78_0 boost_1_78_0.tar.bz2

ENV BOOST_ROOT=/opt/boost_3_11
ENV CMAKE_PREFIX_PATH=/opt/boost_3_11:$CMAKE_PREFIX_PATH
ENV LD_LIBRARY_PATH=/opt/boost_3_11/lib:$LD_LIBRARY_PATH
ENV LIBRARY_PATH=/opt/boost_3_11/lib:$LIBRARY_PATH
ENV CPLUS_INCLUDE_PATH=/opt/boost_3_11/include:$CPLUS_INCLUDE_PATH
ENV PKG_CONFIG_PATH=/opt/boost_3_11/lib/pkgconfig:$PKG_CONFIG_PATH
ENV Boost_NO_SYSTEM_PATHS=ON

# ============================================================
# Python packages after Boost
# ============================================================
RUN python3.11 -m pip uninstall numpy -y || true
RUN python3.11 -m pip install --upgrade pip
RUN python3.11 -m pip install numpy pybind11 PyYAML rospkg
RUN python3.11 -m pip install "pybind11[global]"

RUN ln -sf /usr/include/python3.11 /usr/include/python3

ENV PYTHONPATH=/usr/local/lib/python3.11/dist-packages:/usr/local/lib/python3.11/site-packages
ENV PYTHON_EXECUTABLE=/usr/bin/python3.11
ENV Python3_EXECUTABLE=/usr/bin/python3.11
ENV PYTHON_INCLUDE_DIR=/usr/include/python3.11
ENV PYTHON_LIBRARY=/usr/lib/x86_64-linux-gnu/libpython3.11.so

# Remove system NumPy so Python 3.11 does not import Ubuntu's Python 3.12 NumPy.
RUN apt remove -y python3-numpy || true
RUN python3.11 -m pip install --force-reinstall "numpy<2"
RUN python3.11 -c "import numpy; print(numpy.__file__); print(numpy.get_include())"

# ============================================================
# ROS 2 Jazzy source workspace
# ============================================================
RUN mkdir -p ${ROS_ROOT}/src && \
    cd ${ROS_ROOT} && \
    rosinstall_generator --deps --rosdistro ${ROS_DISTRO} \
        rosidl_runtime_c \
        rcutils \
        rcl \
        rmw \
        tf2 \
        tf2_msgs \
        common_interfaces \
        geometry_msgs \
        nav_msgs \
        std_msgs \
        rosgraph_msgs \
        sensor_msgs \
        vision_msgs \
        rclpy \
        ros2topic \
        ros2pkg \
        ros2doctor \
        ros2run \
        ros2node \
        ros2launch \
        ros_environment \
        ackermann_msgs \
        example_interfaces \
        rclcpp \
        cv_bridge \
        > ros2.${ROS_DISTRO}.rosinstall && \
    vcs import src < ros2.${ROS_DISTRO}.rosinstall

# Patch rclpy for Python 3.11
RUN find /workspace/${ROS_ROOT}/src -name rclpy -type d | \
    xargs -I{} /bin/bash -c 'if [ -f {}/CMakeLists.txt ]; then \
        sed -i "s/include_directories(\${PYTHON_INCLUDE_DIRS})/include_directories(\/usr\/include\/python3.11)/" {}/CMakeLists.txt; \
        sed -i "s/\${PYTHON_LIBRARY}/python3.11/" {}/CMakeLists.txt; \
    fi'

RUN rosdep init && rosdep update

# ============================================================
# Build ROS 2 Jazzy with Python 3.11
# ============================================================
RUN cd ${ROS_ROOT} && \
    NUMPY_INCLUDE=$(python3.11 -c "import numpy; print(numpy.get_include())") && \
    echo "NumPy include: ${NUMPY_INCLUDE}" && \
    colcon build --merge-install --cmake-args \
        "-DPython3_EXECUTABLE=/usr/bin/python3.11" \
        "-DPYTHON_EXECUTABLE=/usr/bin/python3.11" \
        "-DPYTHON_INCLUDE_DIR=/usr/include/python3.11" \
        "-DPYTHON_LIBRARY=/usr/lib/x86_64-linux-gnu/libpython3.11.so" \
        "-DPython3_NumPy_INCLUDE_DIRS=${NUMPY_INCLUDE}" \
        "-DPython3_FIND_STRATEGY=LOCATION" \
        -DBOOST_ROOT=/opt/boost_3_11

# ============================================================
# Pangolin v0.6 patched for Ubuntu 24.04
# ============================================================
RUN cd /workspace && \
    git clone https://github.com/balazsvigh/Pangolin_v06_ubuntu24.git && \
    cd Pangolin_v06_ubuntu24 && \
    mkdir build && \
    cd build && \
    cmake .. \
        -DBUILD_PANGOLIN_PYTHON=OFF \
        -DBUILD_PYTHON=OFF \
        -DBUILD_PYPANGOLIN_MODULE=OFF \
        -DBUILD_PANGOLIN_FFMPEG=OFF \
        -DBUILD_FFMPEG=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TOOLS=OFF && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# ============================================================
# ORB_SLAM3
# ============================================================
RUN test -f /opt/boost_3_11/include/boost/serialization/serialization.hpp && \
    test -f /usr/include/openssl/md5.h && \
    git lfs install && \
    cd /workspace && \
    git clone https://github.com/balazsvigh/ORB_SLAM3_CPP14.git && \
    cd ORB_SLAM3_CPP14 && \
    git lfs pull && \
    chmod +x build.sh && \
    sed -i 's/make -j$(nproc)/make VERBOSE=1 -j1/g' build.sh && \
    sed -i 's/make -j[0-9]\+/make VERBOSE=1 -j1/g' build.sh && \
    sed -i 's/make -j/make VERBOSE=1 -j1/g' build.sh && \
    ./build.sh

ENV ORB_SLAM3_DIR=/workspace/ORB_SLAM3_CPP14
ENV LD_LIBRARY_PATH=/workspace/ORB_SLAM3_CPP14/lib:/opt/boost_3_11/lib:/usr/local/lib:$LD_LIBRARY_PATH

RUN echo "/workspace/ORB_SLAM3_CPP14/lib" > /etc/ld.so.conf.d/orbslam3.conf && \
    echo "/opt/boost_3_11/lib" > /etc/ld.so.conf.d/boost_3_11.conf && \
    echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && \
    ldconfig

# ============================================================
# GUI runtime defaults
# Actual DISPLAY must still be passed with docker run.
# ============================================================
ENV QT_X11_NO_MITSHM=1
ENV LIBGL_ALWAYS_INDIRECT=0

RUN mkdir -p /workspace/build_ws/src

WORKDIR /workspace

CMD ["/bin/bash"]