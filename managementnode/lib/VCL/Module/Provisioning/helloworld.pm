#!/usr/bin/perl -w
###############################################################################
# $Id$
###############################################################################
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

=head1 NAME

VCL::Provisioning::helloworld - VCL module to serve as a template for other provisioning modules

=head1 SYNOPSIS

 Needs to be written

=head1 DESCRIPTION

 This module provides a starting point for other VCL provisioning modules.  To install this module in your VCL installation, create the following three database entries in your vcl database.

1)  Insert a row into the module table with `perlpackage` equal to 'VCL::Module::Provisioning::helloworld'
2)  Insert a row into the provisioning table with `moduleid` equal to the id of the entry from step 1 in the module table
3)  Insert/Modify a row in the computers table with `provisioningid` equal to the id of the entry from step 2 in the provisioning table

Any computer table entry modified according to step 3 will now use the helloworld.pm provisioning module.

=cut

##############################################################################

# this is all traditional VCL stuff
package VCL::Module::Provisioning::helloworld;

# Specify the lib path using FindBin
use FindBin;
use lib "$FindBin::Bin/../../..";

# Configure inheritance
use base qw(VCL::Module::Provisioning);

# Specify the version of this module
our $VERSION = '2.3';

# Specify the version of Perl to use
use 5.008000;

use strict;
use warnings;
use diagnostics;

use VCL::utils;
use Fcntl qw(:DEFAULT :flock);

##############################################################################

=head1 OBJECT METHODS

=cut

#/////////////////////////////////////////////////////////////////////////////

=head2 initialize

 Parameters  :  none
 Returns     :  returns 1 if successfully initialized; 0 otherwise
 Description :  This function is called by vcl when this provisioning module is first initialized by vcl.  This happens before any other methods are called in this module

=cut

sub initialize {
	notify($ERRORS{'DEBUG'}, 0, "Hello World module initialized");
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 provision

 Parameters  : hash
 Returns     : 1(success) or 0(failure)
 Description : loads node with provided image.  This includes, setting up any files (copying or resistering).  Loading the resource.  Turn on the resource.  Wait until the resource is ready to use (after the vm or physical machine has booted).

=cut

sub load {
	my $self = shift;
	if (ref($self) !~ /helloworld/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}
	my $request_data = shift;
	my ($package, $filename, $line, $sub) = caller(0);
	notify($ERRORS{'DEBUG'}, 0, "Hello World, the load method has been successfully called");

	# get various useful vars from the database
	my $request_id     = $self->data->get_request_id;
	my $reservation_id = $self->data->get_reservation_id;
	my $vmhost_hostname           = $self->data->get_vmhost_hostname;
	my $image_name     = $self->data->get_image_name;
	my $computer_shortname  = $self->data->get_computer_short_name;
	my $vmclient_computerid = $self->data->get_computer_id;
	my $vmclient_imageminram      = $self->data->get_image_minram;
	my $image_os_name  = $self->data->get_image_os_name;
	my $image_identity = $self->data->get_image_identity;

	my $virtualswitch0    = $self->data->get_vmhost_profile_virtualswitch0;
	my $virtualswitch1    = $self->data->get_vmhost_profile_virtualswitch1;
	my $vmclient_eth0MAC          = $self->data->get_computer_eth0_mac_address;
	my $vmclient_eth1MAC          = $self->data->get_computer_eth1_mac_address;
	#my $vmclient_privateIP = $self->data->get_computer_private_ip_address;
	my $vmclient_OSname           = $self->data->get_image_os_name;
	#my $vmclient_publicIPaddress  = $self->data->get_computer_private_ip_address;

	return 1;

} ## end sub load

#/////////////////////////////////////////////////////////////////////////////

=head2 capture

 Parameters  : $request_data_hash_reference
 Returns     : 1 if sucessful, 0 if failed
 Description : Saves the image back into the repository.

=cut

sub capture {
	notify($ERRORS{'OK'}, 0, "Hello world, I am capturing an image now");
	return 1;
} ## end sub capture


#/////////////////////////////////////////////////////////////////////////

sub does_image_exist {
	my $self = shift;
	if (ref($self) !~ /helloworld/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}

	my $image_name = $self->data->get_image_name();

	if (!$image_name) {
		notify($ERRORS{'CRITICAL'}, 0, "unable to determine if image exists, unable to determine image name");
		return 0;
	}

	my $IMAGEREPOSITORY = "/mnt/vcl/golden";

	if (open(IMAGES, "/bin/ls -1 $IMAGEREPOSITORY 2>&1 |")) {
		my @images = <IMAGES>;
		close(IMAGES);
		foreach my $i (@images) {
			if ($i =~ /$image_name/) {
				notify($ERRORS{'OK'}, 0, "image $image_name exists");
				return 1;
			}
		}
	} ## end if (open(IMAGES, "/bin/ls -1 $IMAGEREPOSITORY 2>&1 |"...

	notify($ERRORS{'WARNING'}, 0, "image $IMAGEREPOSITORY/$image_name does NOT exists");
	return 0;

} ## end sub does_image_exist

initialize();

#/////////////////////////////////////////////////////////////////////////////

1;
__END__

=head1 SEE ALSO

L<http://cwiki.apache.org/VCL/>

=cut
