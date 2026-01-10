ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}

ENV ROS_DISTRO=humble
ENV ROS_ROOT=humble_ws
ENV ROS_PYTHON_VERSION=3
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /workspace

# ----------------------------
# Install basic tools
# ----------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake build-essential curl wget gnupg2 lsb-release software-properties-common

RUN apt update && apt upgrade -y && apt clean

# ----------------------------
# Install Python 3.11
# ----------------------------
RUN add-apt-repository -y ppa:deadsnakes/ppa && \
    apt install --no-install-recommends -y python3.11 python3.11-dev python3.11-distutils python3.11-venv && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# ----------------------------
# Install pip for Python 3.11
# ----------------------------
RUN curl -s https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.11 get-pip.py --force-reinstall && rm get-pip.py

# ----------------------------
# Locale
# ----------------------------
RUN apt update && apt install -y locales && \
    locale-gen en_US en_US.UTF-8 && \
    update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

# ----------------------------
# ROS 2 keys and sources
# ----------------------------
RUN wget https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc && apt-key add ros.asc && \
    sh -c 'echo "deb [arch=$(dpkg --print-architecture)] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/ros2-latest.list'

# ----------------------------
# Install system dependencies
# ----------------------------
RUN apt update && apt install -y --no-install-recommends \
    pkg-config python3-yaml cmake-extras \
    libqhull-dev libassimp-dev liboctomap-dev libconsole-bridge-dev libfcl-dev \
    libeigen3-dev \
    libx11-dev libxaw7-dev libxrandr-dev libgl1-mesa-dev libglu1-mesa-dev \
    libglew-dev libgles2-mesa-dev libopengl-dev libfreetype-dev libfreetype6-dev libfontconfig1-dev libfmt-dev \
    qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools \
    libqt5core5a libqt5gui5 libqt5opengl5 libqt5widgets5 \
    libxcursor-dev libxinerama-dev libxi-dev libyaml-cpp-dev \
    libzzip-dev freeglut3-dev libogre-1.9-dev libpng-dev libjpeg-dev python3-pyqt5.qtwebengine \
    python3-pip python3-pytest-cov python3-rosinstall-generator ros-dev-tools \
    libbullet-dev libasio-dev libtinyxml2-dev libcunit1-dev libacl1-dev python3-empy libpython3-dev \
    wget curl git build-essential \
    libopencv-dev python3-opencv \
    gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev

# ----------------------------
# Upgrade pip & install Python packages
# ----------------------------
RUN python3.11 -m pip install --upgrade pip setuptools==70.0.0
RUN python3.11 -m pip install empy==3.3.4 lark colcon-common-extensions

# ----------------------------
# Build Boost 1.78 for Python 3.11
# ----------------------------
RUN cd /workspace && \
    wget https://sourceforge.net/projects/boost/files/boost/1.78.0/boost_1_78_0.tar.bz2/download -O boost_1_78_0.tar.bz2 && \
    tar xf boost_1_78_0.tar.bz2 && \
    cd boost_1_78_0 && \
    ./bootstrap.sh --with-python=/usr/bin/python3.11 --prefix=/opt/boost_3_11 && \
    ./b2 install threading=multi variant=release link=shared python=3.11 && \
    cd .. && rm -rf boost_1_78_0 boost_1_78_0.tar.bz2

ENV BOOST_ROOT=/opt/boost_3_11
ENV CMAKE_PREFIX_PATH=/opt/boost_3_11:$CMAKE_PREFIX_PATH
ENV LD_LIBRARY_PATH=/opt/boost_3_11/lib:$LD_LIBRARY_PATH
ENV PKG_CONFIG_PATH=/opt/boost_3_11/lib/pkgconfig:$PKG_CONFIG_PATH
ENV Boost_NO_SYSTEM_PATHS=ON

RUN python3.11 -m pip uninstall numpy -y
RUN python3.11 -m pip install --upgrade pip
RUN python3.11 -m pip install numpy pybind11 PyYAML

# Create symlinks for Python3.11 headers where CMake can find them
RUN ln -sf /usr/include/python3.11 /usr/include/python3

# Fix paths for pybind11
RUN python3.11 -m pip install "pybind11[global]"

# ----------------------------
# ROS 2 workspace setup
# ----------------------------
RUN mkdir -p ${ROS_ROOT}/src && cd ${ROS_ROOT} && \
    rosinstall_generator --deps --rosdistro ${ROS_DISTRO} \
        rosidl_runtime_c rcutils rcl rmw tf2 tf2_msgs common_interfaces \
        geometry_msgs nav_msgs std_msgs rosgraph_msgs sensor_msgs vision_msgs \
        rclpy ros2topic ros2pkg ros2doctor ros2run ros2node ros2launch ros_environment \
        ackermann_msgs example_interfaces rclcpp cv_bridge > ros2.${ROS_DISTRO}.rosinstall && \
    vcs import src < ros2.${ROS_DISTRO}.rosinstall

# Patch rclpy for Python 3.11
RUN find /workspace/${ROS_ROOT}/src -name rclpy -type d | xargs -I{} /bin/bash -c 'if [ -f {}/CMakeLists.txt ]; then \
    sed -i "s/include_directories(\${PYTHON_INCLUDE_DIRS})/include_directories(\/usr\/include\/python3.11)/" {}/CMakeLists.txt; \
    sed -i "s/\${PYTHON_LIBRARY}/python3.11/" {}/CMakeLists.txt; fi'

# Initialize rosdep
RUN rosdep init && rosdep update

ENV PYTHONPATH=/usr/local/lib/python3.11/dist-packages

# ----------------------------
# Build ROS 2 Humble with Python 3.11 and custom Boost
# ----------------------------
RUN cd ${ROS_ROOT} && colcon build --cmake-args \
    "-DPython3_EXECUTABLE=/usr/bin/python3.11" \
    "-DPYTHON_EXECUTABLE=/usr/bin/python3.11" \
    "-DPYTHON_INCLUDE_DIR=/usr/include/python3.11" \
    "-DPYTHON_LIBRARY=/usr/lib/x86_64-linux-gnu/libpython3.11.so" \
    -DBOOST_ROOT=/opt/boost_3_11 \
    --merge-install

# ----------------------------
# Copy your workspace and build it
# ----------------------------
RUN mkdir -p /workspace/build_ws/src
COPY humble_ws/src /workspace/build_ws/src
RUN rm -rf /workspace/build_ws/src/moveit

WORKDIR /workspace
RUN /bin/bash -c "source ${ROS_ROOT}/install/setup.sh && cd build_ws && colcon build \
    --cmake-args \
        '-DPython3_EXECUTABLE=/usr/bin/python3.11' \
        '-DPYTHON_INCLUDE_DIR=/usr/include/python3.11' \
        '-DPYTHON_LIBRARY=/usr/lib/x86_64-linux-gnu/libpython3.11.so' \
        -DBOOST_ROOT=/opt/boost_3_11"
