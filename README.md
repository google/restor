# Restor

Restor is a user-friendly application to (mass) image macOS computers from a
single source. It is an application intended to be run interactively on a
machine.

<p align="center">
<a href="#restor--">
<img src="./images/restor.png" alt="Restor" />
</a>
</p>

You can attach the machine-to-be-imaged via Thunderbolt or USB to the machine
running Restor.

<p align="center">
<a href="#restor_disk_choice--">
<img src="./images/restor_disk_choice.png" alt="Restor Disk Choice" />
</a>
</p>

Restor will cache an image once it has been downloaded for future use, and will
validate the image via SHA256. Only if the signature has changed, will the image
be downloaded again.

<p align="center">
<a href="#restor_progress--">
<img src="./images/restor_progress.png" alt="Restor Download Progress" />
</a>
</p>

<p align="center">
<a href="#restor_validate--">
<img src="./images/restor_validate.png" alt="Restor Image Validation" />
</a>
</p>

# Example Configuration

Restor has a few configurable options, 1 of which is required. These can be
specified using a local plist (stored at `/Library/Preferences/com.google.corp.restor.plist`)
or using a Configuration Profile for the com.google.corp.restor domain.

### ConfigURL

__Required__

Set the `ConfigURL` preference to point at a plist containing the images to be
used.

`sudo defaults write /Library/Preferences/com.google.corp.restor.plist ConfigURL "http://server/images.plist"`

The following format for the plist is required:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Images</key>
	<array>
		<dict>
			<key>Name</key>
			<string>Sierra (10.12) All Models</string>
			<key>URL</key>
			<string>http://server/10.12.6.dmg</string>
			<key>SHA-256</key>
			<string>ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff</string>
		</dict>
	</array>
</dict>
</plist>
```

### CustomImage

__Optional__

Set the `CustomImage` preference to toggle the use of a local custom image.

`sudo defaults write /Library/Preferences/com.google.corp.restor.plist CustomImage -bool true`

### ConfigCheckInterval

__Optional__

Set how often Restor should download and validate the image configuration in the background.
Specified in seconds, defaults to 900 (15 minutes).

`sudo defaults write /Library/Preferences/com.google.corp.restor.plist ConfigCheckInterval -int 600`

### DiskFilterPredicate

__Optional__

Allows you to customize which disks will appear in the Restor UI (or that will
be imaged automatically in auto-image mode). The default predicates, which
cannot be overridden, will filter out internal disks and system volumes such
as Recovery, VM, Preboot, etc. This key allows you to specify, using
[NSPredicate](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Predicates/AdditionalChapters/Introduction.html#//apple_ref/doc/uid/TP40001789)
other disks which should not be shown to the user. You can use any of the properties
on the [Disk](https://github.com/google/restor/blob/master/Common/Disk.h#L26)
object to create your predicate.

You can also pass the `--debug-disk-filters` flag to Restor.app to see what effects the predicate is having.

Examples:

* Filter out disks larger than 5TB:

```shell
sudo defaults write /Library/Preferences/com.google.corp.restor.plist DiskFilterPredicate -string \
    "(diskSize < 5497558138880)"
```

* Filter out disks made by Seagate:

```shell
sudo defaults write /Library/Preferences/com.google.corp.restor.plist DiskFilterPredicate -string \
    "(deviceVendor != 'Seagate')"
```

* Filter out disks by their id:

```shell
sudo defaults write /Library/Preferences/com.google.corp.restor.plist DiskFilterPredicate -string \
    "(bsdName != 'disk3s2')"
```

## 10.13 and APFS Note

In order to restore an APFS 10.13 DMG to a machine, the host machine running
Restor must also be upgraded to High Sierra 10.13. Otherwise, you will receive
an error when attempting to image the machine.

<p align="center">
<a href="#restor_apfs_error--">
<img src="./images/restor_apfs_error.png" alt="Restor APFS Error" />
</a>
</p>

## Building from source

Building Restor from source is _not_ required for general usage. Please see the
[Releases](https://github.com/google/restor/releases) page to download a
pre-compiled version of Restor.

#### Requirements

* Xcode 9+ installed
* [cocoapods](https://cocoapods.org) installed
* A valid "Mac Developer" Signing Certificate from Apple
* Xcode command line tools installed

#### Build steps

1. `git clone https://github.com/google/restor.git`
1. `cd restor`
1. `pod install`
1. Find your Team Identifer. Manually selecting the correct Team Identifier might be required if you have multiple developer certificates.
    ```bash
    security find-certificate -p -c "Mac Developer" | openssl x509 -inform pem -subject | perl -ne '/OU=(\w+)\// && print $1'
    ```
1. Build with the following command, making sure to insert a valid Team Identifier from the previous step.
    ```bash
    make release TEAM_ID=EQHXZ8M8AV
    ```

If the build was successful the last line will contain the path to your
compiled Restor.app.

## Contributing

Patches to this library are very much welcome. Please see the
[CONTRIBUTING](https://github.com/google/restor/blob/master/CONTRIBUTING.md)
file.
