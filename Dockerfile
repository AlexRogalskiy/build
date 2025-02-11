# Builds a docker image used for building most projects in this repo. It's
# used both by contributors and CI.
#
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --assume-yes \
    locales

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app

# Include universe repositories for EOLed versions
RUN apt-get update \
    && apt-get install --assume-yes  \
    software-properties-common \
    && add-apt-repository universe

RUN apt-get update \
    && apt-get install --assume-yes  \
    bash \
    cmake \
    curl \
    diffutils \
    golang-go \
    git \
    gnupg \
    groff \
    g++ \
    jq \
    libc-dev \
    libssl-dev \
    libxml2-dev \
    libxslt-dev \
    make \
    maven \
    openjdk-8-jdk \
    openjdk-11-jdk \
    openssl \
    perl \
    protobuf-compiler \
    python2 \
    pipenv \
    rsync \
    ruby \
    ruby-dev \
    ruby-json \
    rubygems \
    sed \
    tree \
    unzip \
    upx \
    xmlstarlet

# Create a cukebot user. Some tools (Bundler, npm publish) don't work properly
# when run as root
ENV USER=cukebot
ENV UID=1000
ENV GID=2000

RUN addgroup --gid "$GID" "$USER" \
    && adduser \
    --disabled-password \
    --gecos "" \
    --ingroup "$USER" \
    --uid "$UID" \
    --shell /bin/bash \
    "$USER"

ARG TARGETARCH

# Configure Maven and Java
ENV JAVA_HOME /usr/lib/jvm/java-11-openjdk-$TARGETARCH
COPY --chown=$USER toolchains.xml /home/$USER/.m2/toolchains.xml
COPY --chown=$USER settings.xml /home/$USER/.m2/settings.xml

# Configure Ruby
RUN echo "gem: --no-document" > ~/.gemrc \
    && gem install bundler io-console nokogiri \
    && chown -R $USER:$USER /usr/lib/ruby  \
    && chown -R $USER:$USER /usr/local/bin \
    && chown -R $USER:$USER /var/lib \
    && chown -R $USER:$USER /usr/bin

# Install and configure pip2, twine and behave
RUN curl -sSL https://bootstrap.pypa.io/pip/2.7/get-pip.py -o get-pip.py \
    && echo "0adb06840d8a9e9d8edc4bb9137d1ca99e75fd61 *get-pip.py" | sha1sum -c --quiet - \
    && cat get-pip.py | python2 \
    && pip install pipenv \
    && pip install twine \
    && pip install behave \
    && rm get-pip.py

# Configure Perl
RUN curl -sSL https://cpanmin.us/ -o /usr/local/bin/cpanm \
    && cd /usr/local/bin/ && echo "09c682a9c6d7c47967bba91909378072921c12d0  cpanm" | sha1sum -c --quiet - && cd /app \
    && chmod +x /usr/local/bin/cpanm \
    && cpanm --notest Carton \
    && rm -rf /root/.cpanm

# Install hub
RUN git clone \
    -b v2.12.2 --single-branch --depth 1 \
    --config transfer.fsckobjects=false \
    --config receive.fsckobjects=false \
    --config fetch.fsckobjects=false \
    https://github.com/github/hub.git  \
    && cd hub  \
    && make  \
    && cp bin/hub /usr/local/bin/hub \
    && cd .. \
    && rm -r hub

# Install splitsh/lite
RUN go get -d github.com/libgit2/git2go \
    && cd $(go env GOPATH)/src/github.com/libgit2/git2go \
    && git checkout next \
    && git submodule update --init \
    && make install \
    && go get github.com/splitsh/lite \
    && go build -o /usr/local/bin/splitsh-lite github.com/splitsh/lite

# Install .NET Core
# https://github.com/dotnet/dotnet-docker/blob/5c25dd2ed863dfd73edb1a6381dd9635734d0e5f/2.2/sdk/bionic/amd64/Dockerfile
ENV DOTNET_CLI_TELEMETRY_OPTOUT=true
## Install .NET CLI dependencies
RUN apt-get update \
    && apt-get install --assume-yes --no-install-recommends \
    libc6 \
    libgcc1 \
    libgssapi-krb5-2 \
    liblttng-ust0 \
    libstdc++6 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

## Install .NET Core SDK
ENV DOTNET_SDK_VERSION 5.0

RUN curl -sSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh \
    && echo "25b457ce8170a34f74649632660c40a5cfd355a1  dotnet-install.sh" | sha1sum -c --quiet - \ 
    && cat dotnet-install.sh | bash -s -- -c $DOTNET_SDK_VERSION --install-dir /usr/share/dotnet \
    && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
    && rm dotnet-install.sh

## Trigger first run experience by running arbitrary cmd to populate local package cache
RUN dotnet --list-sdks

# Install Berp
RUN curl -sSL https://www.nuget.org/api/v2/package/Berp/1.1.1 -o berp.zip \
    && echo "f558782cf8eb9143ab8e7f7e3ad1607f7fea512e  berp.zip" | sha1sum -c --quiet - \
    && mkdir -p /var/lib/berp \
    && unzip berp.zip -d /var/lib/berp/1.1.1 \
    && rm berp.zip

# Install JS
## Install yarn without node
RUN apt-get update \
    && apt-get install --assume-yes --no-install-recommends yarn

# Install sbt
RUN curl -sSL https://repo.scala-sbt.org/scalasbt/debian/sbt-1.5.1.deb -o sbt.deb \
    && echo "1823777aa853fefe2e535f2b1eb9ec0ad89d8621  sbt.deb" | sha1sum -c --quiet - \
    && dpkg -i sbt.deb \
    && rm -f sbt.deb
# Configure sbt
COPY --chown=$USER sonatype.sbt /home/$USER/.sbt/1.0/sonatype.sbt

# Install sqlite3 - Required for cucumber-rails
RUN apt-get update \
    && apt-get install --assume-yes --no-install-recommends \
    ca-certificates \
    sqlite3 \
    libsqlite3-dev

# Download and install chromium for puppetteer
COPY scripts/download-chrome.sh .
RUN bash ./download-chrome.sh
RUN rm ./download-chrome.sh

# Puppetteer seems to need the binary to be called chromium-browser
RUN ln -s /usr/bin/chromium /usr/bin/chromium-browser

# Install Elixir
ENV MIX_HOME=/home/cukebot/.mix
RUN curl -sSL https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb -o erlang.deb \
    && echo "1968ec2ae81a5e1f56d2f173144926ec90a5e7c7  erlang.deb" | sha1sum -c --quiet - \ 
    && dpkg -i erlang.deb \
    && apt-get update \
    && apt-get install --assume-yes --no-install-recommends \
    esl-erlang \
    elixir \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f erlang.deb

# Install Dart
RUN apt-get update && apt-get install wget
COPY scripts/install-dart.sh .
RUN bash ./install-dart.sh
RUN rm ./install-dart.sh

USER $USER

## As a user install node and npm via node version-manager
WORKDIR /home/$USER
RUN curl -sSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.2/install.sh -o install-nvm.sh \
    && echo "5a59afa6936f42ceb8e239a6cb191f03cefaa741  install-nvm.sh" | sha1sum -c --quiet - \ 
    && cat install-nvm.sh | bash \
    && export NVM_DIR="$HOME/.nvm" \
    && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" \
    && [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" \
    && nvm install 14.17.3 \
    && nvm install-latest-npm \
    && rm install-nvm.sh
WORKDIR /app

CMD ["/bin/bash"]
