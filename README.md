# AWS_DB_Cloner

This script is a simple clone / copy helper for AWS RDS. It takes an existing, running database, and in order:

* Makes a snapshot of the existing, running database
* Encrypts that snapshot
* Spins out a new database beside the DB in the same region

Depending on the size of your database, this could take some time. 

## To do:

* Clean out old junk functions and other cruft from "experiments"
* Optimize the if-else portion of the code for encryption
