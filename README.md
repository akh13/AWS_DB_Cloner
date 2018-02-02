# AWS_DB_Cloner

This script is a simple clone / copy helper for AWS RDS. It takes an existing, running database, and in order:

* Makes a snapshot of the (unencrypted) database
* Encrypts that snapshot
* Spins out a new database beside the DB in the same region

Depending on the size of your database, this could take some time. 

## To do:

* Add option to encrypt or not to encrypt resulting DB
* Clean out old junk functions and other cruft from "experiments"
