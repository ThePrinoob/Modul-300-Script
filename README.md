# Modul 300 LB1 Script
## Whats this?
This is a Script for the GIBB Modul 300. It installs and configures the services required for the LB1.

It can be that functions change over the years. So feel free and change the code to your demands and likings.

## Usage

```sudo ./M300.sh PARAMETER```

The script must be run as sudo, because many opperations depend on it!

Most of the configs that you need to make will be asked and then wrote to the system.


### Parameters
 - ```-f```:         Fully installs and configures bind, apache and ftp

 - ```-apache```:    Only installs and configures apache

 - ```-bind```:      Only installs and configures bind

 - ```-ftp```:       Only installs and configures ftp

### Example Usage
In order to only install Apache and Bind on to the system you can use this command:

 - ```sudo ./M300.sh -apache -bind```

## Known Issues
The netplan DNS server will not be changed automatically and must be set manually.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Reporting Issues

If you have suggestions, bugs or other issues specific to this script, file them [here](https://github.com/ThePrinoob/Modul-300-Script/issues). Or just send me a pull request.