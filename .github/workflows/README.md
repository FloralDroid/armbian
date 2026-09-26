# Runners requirements

- big (6-16 cores, 64Gb SSD, 16Gb memory, 2Gb swap)
- small (4 cores, 64Gb SSD, 8Gb memory, 2Gb swap)

## Preparation



Adding x86 runner to your Jammy VM (check [here](https://docs.github.com/en/actions/hosting-your-own-runners/adding-self-hosted-runners) if any changes):

    $ mkdir actions-runner 
    $ cd actions-runner
    $ curl -o actions-runner-linux-x64-2.294.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.294.0/actions-runner-linux-x64-2.294.0.tar.gz
    $ tar xzf ./actions-runner-linux-x64-2.294.0.tar.gz

## Configuration

Once asked, tag your runner accordingly:

- small
- big
- arm64

Start the configuration experience

    $ ./config.sh --url https://github.com/armbian --token XXXXXXXXXXXXXXXXXXXXXXXXXXX

You need to get a valid token from our DevOps team to proceed.

## Create startup scripts

    sudo ./svc.sh install # install
    sudo ./svc.sh start   # start
    sudo ./svc.sh status  # check
