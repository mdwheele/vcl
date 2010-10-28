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

VCL::Module::OS.pm - VCL base operating system module

=head1 SYNOPSIS

 Needs to be written

=head1 DESCRIPTION

 This module provides VCL support operating systems.

=cut

##############################################################################
package VCL::Module::OS;

# Specify the lib path using FindBin
use FindBin;
use lib "$FindBin::Bin/../..";

# Configure inheritance
use base qw(VCL::Module);

# Specify the version of this module
our $VERSION = '2.00';

# Specify the version of Perl to use
use 5.008000;

use strict;
use warnings;
use diagnostics;
use English '-no_match_vars';
use VCL::utils;

##############################################################################

=head1 OBJECT METHODS

=cut

#/////////////////////////////////////////////////////////////////////////////

=head2 get_source_configuration_directories

 Parameters  : None
 Returns     : Array containing filesystem path strings
 Description : Retrieves the $SOURCE_CONFIGURATION_DIRECTORY variable value for
               the classes which the OS object is a member of and returns an
               array containing these values.
               
               The first element of the array contains the value from the
               top-most class where the $SOURCE_CONFIGURATION_DIRECTORY variable
               was defined. The last element contains the value from the
               bottom-most class, which is probably the class which was
               instantiated.
               
               Example: An Windows XP OS object is instantiated from the XP
               class, which is a subclass of the Version_5 class, which is a
               subclass of the Windows class:
               
               VCL::Module::OS::Windows
               ^
               VCL::Module::OS::Windows::Version_5
               ^
               VCL::Module::OS::Windows::Version_5::XP
               
               The XP and Windows classes each
               have a $SOURCE_CONFIGURATION_DIRECTORY variable defined but the
               Version_5 class does not. The array returned will be:
               
               [0] = '/usr/local/vcldev/current/bin/../tools/Windows'
               [1] = '/usr/local/vcldev/current/bin/../tools/Windows_XP'

=cut

sub get_source_configuration_directories {
	my $self = shift;
	unless (ref($self) && $self->isa('VCL::Module')) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine can only be called as a VCL module object method");
		return;	
	}
	
	# Get an array containing the names of the Perl packages the OS object is a class of
	my @package_hierarchy = $self->get_package_hierarchy();
	
	# Loop through each classes, retrieve any which have a $SOURCE_CONFIGURATION_DIRECTORY variable defined
	my @directories = ();
	for my $package_name (@package_hierarchy) {
		my $source_configuration_directory = eval '$' . $package_name . '::SOURCE_CONFIGURATION_DIRECTORY';
		if ($EVAL_ERROR) {
			notify($ERRORS{'WARNING'}, 0, "unable to determine source configuration directory for $package_name, error:\n$EVAL_ERROR");
			next;	
		}
		elsif (!$source_configuration_directory) {
			notify($ERRORS{'DEBUG'}, 0, "source configuration directory is not defined for $package_name");
			next;
		}
		
		notify($ERRORS{'DEBUG'}, 0, "package source configuration directory: $source_configuration_directory");
		
		# Add the directory path to the return array
		# Use unshift to add to the beginning to the array
		unshift @directories, $source_configuration_directory; 
	}
	
	return @directories;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_currentimage_txt_contents

 Parameters  : None
 Returns     : If successful: array
               If failed: false
 Description : Reads the currentimage.txt file on a computer and returns its
               contents as an array. Each array element represents a line in
               the file.

=cut

sub get_currentimage_txt_contents {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $management_node_keys = $self->data->get_management_node_keys();
	my $computer_node_name   = $self->data->get_computer_node_name();

	# Attempt to retrieve the contents of currentimage.txt
	my $cat_command = "cat ~/currentimage.txt";
	my ($cat_exit_status, $cat_output) = run_ssh_command($computer_node_name, $management_node_keys, $cat_command, '', '', 0);
	if (defined($cat_exit_status) && $cat_exit_status == 0) {
		notify($ERRORS{'DEBUG'}, 0, "retrieved currentimage.txt contents from $computer_node_name");
	}
	elsif (defined($cat_exit_status)) {
		notify($ERRORS{'WARNING'}, 0, "failed to retrieve currentimage.txt from $computer_node_name, exit status: $cat_exit_status, output:\n@{$cat_output}");
		return;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to run ssh command to failed to retrieve currentimage.txt from $computer_node_name");
		return;
	}

	notify($ERRORS{'DEBUG'}, 0, "found " . @{$cat_output} . " lines in currentimage.txt on $computer_node_name");

	return @{$cat_output};
} ## end sub get_currentimage_txt_contents

#/////////////////////////////////////////////////////////////////////////////

=head2 get_current_image_name

 Parameters  : None
 Returns     : If successful: string
               If failed: false
 Description : Reads the currentimage.txt file on a computer and returns a
               string containing the name of the loaded image.

=cut

sub get_current_image_name {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $computer_node_name = $self->data->get_computer_node_name();

	# Get the contents of the currentimage.txt file
	my @current_image_txt_contents;
	if (@current_image_txt_contents = $self->get_currentimage_txt_contents()) {
		notify($ERRORS{'DEBUG'}, 0, "retrieved currentimage.txt contents from $computer_node_name");
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to retrieve currentimage.txt contents from $computer_node_name");
		return;
	}

	# Make sure an empty array wasn't returned
	if (defined $current_image_txt_contents[0]) {
		my $current_image_name = $current_image_txt_contents[0];

		# Remove any line break characters
		$current_image_name =~ s/[\r\n]*//g;

		notify($ERRORS{'DEBUG'}, 0, "name of image currently loaded on $computer_node_name: $current_image_name");
		return $current_image_name;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "empty array was returned when currentimage.txt contents were retrieved from $computer_node_name");
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 wait_for_ping

 Parameters  : Maximum number of seconds to wait (optional), delay between attempts (optional)
 Returns     : If computer is pingable before the maximum amount of time has elapsed: 1
               If computer never responds to ping before the maximum amount of time has elapsed: 0
 Description : Attempts to ping the computer specified in the DataStructure
               for the current reservation. It will wait up to a maximum number
               of seconds. This can be specified by passing the subroutine an
               integer value or the default value of 300 seconds will be used. The
               delay between attempts can be specified as the 2nd argument in
               seconds. The default value is 15 seconds.

=cut

sub wait_for_ping {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Attempt to get the total number of seconds to wait from the arguments
	my $total_wait_seconds = shift;
	if (!defined($total_wait_seconds) || $total_wait_seconds !~ /^\d+$/) {
		$total_wait_seconds = 300;
	}
	
	# Seconds to wait in between loop attempts
	my $attempt_delay_seconds = shift;
	if (!defined($attempt_delay_seconds) || $attempt_delay_seconds !~ /^\d+$/) {
		$attempt_delay_seconds = 15;
	}
	
	my $computer_node_name = $self->data->get_computer_node_name();
	
	my $message = "waiting for $computer_node_name to respond to ping";
	
	# Call code_loop_timeout, specifify that it should call _pingnode with the computer name as the argument
	return $self->code_loop_timeout(\&_pingnode, [$computer_node_name], $message, $total_wait_seconds, $attempt_delay_seconds);
} ## end sub wait_for_ping

#/////////////////////////////////////////////////////////////////////////////

=head2 wait_for_no_ping

 Parameters  : Maximum number of seconds to wait (optional), seconds to delay between attempts (optional)
 Returns     : 1 if computer is not pingable, 0 otherwise
 Description : Attempts to ping the computer specified in the DataStructure
               for the current reservation. It will wait up to a maximum number
               of seconds for ping to fail. The delay between attempts can be
               specified as the 2nd argument in seconds. The default value is 15
               seconds.

=cut

sub wait_for_no_ping {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Attempt to get the total number of seconds to wait from the arguments
	my $total_wait_seconds = shift;
	if (!defined($total_wait_seconds) || $total_wait_seconds !~ /^\d+$/) {
		$total_wait_seconds = 300;
	}
	
	# Seconds to wait in between loop attempts
	my $attempt_delay_seconds = shift;
	if (!defined($attempt_delay_seconds) || $attempt_delay_seconds !~ /^\d+$/) {
		$attempt_delay_seconds = 15;
	}
	
	my $computer_node_name = $self->data->get_computer_node_name();
	
	my $message = "waiting for $computer_node_name to NOT respond to ping";
	
	# Call code_loop_timeout and invert the result, specifify that it should call _pingnode with the computer name as the argument
	return $self->code_loop_timeout(sub{return !_pingnode(@_)}, [$computer_node_name], $message, $total_wait_seconds, $attempt_delay_seconds);
} ## end sub wait_for_no_ping

#/////////////////////////////////////////////////////////////////////////////

=head2 wait_for_ssh

 Parameters  : Seconds to wait (optional), seconds to delay between attempts (optional)
 Returns     : 
 Description : Attempts to communicate to the reservation computer via SSH.
               SSH attempts are made until the maximum number of seconds has
               elapsed. The maximum number of seconds can be specified as the
               first argument. If an argument isn't supplied, a default value of
               300 seconds will be used.
               
               A delay occurs between attempts. This can be specified by passing
               a 2nd argument. If a 2nd argument isn't supplied, a default value
               of 15 seconds will be used.

=cut

sub wait_for_ssh {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Attempt to get the total number of seconds to wait from the arguments
	my $total_wait_seconds = shift;
	if (!defined($total_wait_seconds) || $total_wait_seconds !~ /^\d+$/) {
		$total_wait_seconds = 300;
	}
	
	# Seconds to wait in between loop attempts
	my $attempt_delay_seconds = shift;
	if (!defined($attempt_delay_seconds) || $attempt_delay_seconds !~ /^\d+$/) {
		$attempt_delay_seconds = 15;
	}
	
	my $computer_node_name = $self->data->get_computer_node_name();
	
	# Call the "can" function, it returns a code reference to the subroutine specified
	# This is passed to code_loop_timeout which will then execute the code until it returns true
	my $sub_ref = $self->can("is_ssh_responding");
	
	my $message = "waiting for $computer_node_name to respond to SSH";

	return $self->code_loop_timeout($sub_ref, [$self], $message, $total_wait_seconds, $attempt_delay_seconds);
}

#/////////////////////////////////////////////////////////////////////////////

=head2 is_ssh_responding

 Parameters  : None
 Returns     : If computer responds to SSH: 1
               If computer never responds to SSH: 0
 Description : Checks if the reservation computer is responding to SSH.

=cut

sub is_ssh_responding {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	my $computer_node_name = $self->data->get_computer_node_name();
	
	# Try nmap to see if any of the ssh ports are open before attempting to run a test command
	my $port_22_status = nmap_port($computer_node_name, 22) ? "open" : "closed";
	my $port_24_status = nmap_port($computer_node_name, 24) ? "open" : "closed";
	if ($port_22_status ne 'open' && $port_24_status ne 'open') {
		notify($ERRORS{'DEBUG'}, 0, "$computer_node_name is NOT responding to SSH, ports 22 or 24 are both closed");
		return 0;
	}
	
	# Run a test SSH command
	my ($exit_status, $output) = run_ssh_command({
		node => $computer_node_name,
		command => "echo testing ssh on $computer_node_name",
		max_attempts => 1,
		output_level => 0,
	});
	
	# The exit status will be 0 if the command succeeded
	if (defined($output) && grep(/testing/, @$output)) {
		notify($ERRORS{'DEBUG'}, 0, "$computer_node_name is responding to SSH, port 22: $port_22_status, port 24: $port_24_status");
		return 1;
	}
	else {
		notify($ERRORS{'DEBUG'}, 0, "$computer_node_name is NOT responding to SSH, SSH command failed, port 22: $port_22_status, port 24: $port_24_status");
		return 0;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 wait_for_response

 Parameters  : Initial delay seconds (optional), SSH response timeout seconds (optional), SSH attempt delay seconds (optional)
 Returns     : If successful: true
               If failed: false
 Description : Waits for the reservation computer to respond to SSH after it
               has been loaded.

=cut

sub wait_for_response {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	my $start_time = time();
	
	my $reservation_id = $self->data->get_reservation_id();
	my $computer_id = $self->data->get_computer_id();
	my $computer_node_name = $self->data->get_computer_node_name();
	
	my $initial_delay_seconds = shift;
	if (!defined $initial_delay_seconds) {
		$initial_delay_seconds = 120;
	}
	
	my $ssh_response_timeout_seconds = shift;
	if (!defined $ssh_response_timeout_seconds) {
		$ssh_response_timeout_seconds = 600;
	}
	
	my $ssh_attempt_delay_seconds = shift;
	if (!defined $ssh_attempt_delay_seconds) {
		$ssh_response_timeout_seconds = 15;
	}
	
	# Sleep for the initial delay value if it has been set
	# Check SSH once to bypass the initial delay if SSH is already responding
	if ($initial_delay_seconds && !$self->is_ssh_responding()) {
		notify($ERRORS{'OK'}, 0, "waiting $initial_delay_seconds seconds for $computer_node_name to boot");
		sleep $initial_delay_seconds;
		notify($ERRORS{'OK'}, 0, "waited $initial_delay_seconds seconds for $computer_node_name to boot");
	}
	
	# Wait for SSH to respond, loop until timeout is reached
	notify($ERRORS{'OK'}, 0, "waiting for $computer_node_name to respond to SSH, maximum of $ssh_response_timeout_seconds seconds");
	if (!$self->wait_for_ssh($ssh_response_timeout_seconds, $ssh_attempt_delay_seconds)) {
		notify($ERRORS{'WARNING'}, 0, "failed to connect to $computer_node_name via SSH after $ssh_response_timeout_seconds seconds");
		return;
	}
	
	my $end_time = time();
	my $duration = ($end_time - $start_time);
	
	#insertloadlog($reservation_id, $computer_id, "osrespond", "$computer_node_name is responding to SSH after $duration seconds");
	notify($ERRORS{'OK'}, 0, "$computer_node_name is responding to SSH after $duration seconds");
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 update_ssh_known_hosts

 Parameters  : $known_hosts_path (optional)
 Returns     : boolean
 Description : Removes lines from the known_hosts file matching the computer
               name or private IP address, then runs ssh-keyscan to add the
               current keys to the known_hosts file.

=cut

sub update_ssh_known_hosts {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	my $known_hosts_path = shift || "/root/.ssh/known_hosts";
	
	my $computer_short_name = $self->data->get_computer_short_name();
	
	# Get the computer private IP address
	my $computer_private_ip_address;
	if ($self->can("get_private_ip_address") && ($computer_private_ip_address = $self->get_private_ip_address())) {
		notify($ERRORS{'DEBUG'}, 0, "retrieved private IP address for $computer_short_name using OS module: $computer_private_ip_address");
	}
	elsif ($computer_private_ip_address = $self->data->get_computer_private_ip_address()) {
		notify($ERRORS{'DEBUG'}, 0, "retrieved private IP address for $computer_short_name from database: $computer_private_ip_address");
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve private IP address for $computer_short_name using OS module or from database");
	}
	
	# Open the file, read the contents into an array, then close it
	my @known_hosts_lines_original;
	if (open FILE, "<", $known_hosts_path) {
		@known_hosts_lines_original = <FILE>;
		close FILE;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unable to open file for reading: $known_hosts_path");
		return;
	}
	
	
	# Loop through the lines
	my @known_hosts_lines_modified;
	for my $line (@known_hosts_lines_original) {
		chomp $line;
		next if (!$line);
		
		# Check if line matches the computer name or private IP address
		if ($line =~ /(^|[\s,])$computer_short_name[\s,]/i) {
			# Don't add the line to the array which will be added back to the file
			notify($ERRORS{'DEBUG'}, 0, "removing line from $known_hosts_path matching computer name: $computer_short_name\n$line");
			next;
		}
		elsif ($line =~ /(^|[\s,])$computer_private_ip_address[\s,]/i) {
			notify($ERRORS{'DEBUG'}, 0, "removing line from $known_hosts_path matching computer private IP address:$computer_private_ip_address\n$line");
			next;
		}
		
		# Line doesn't match, add it to the array of lines for the new file
		push @known_hosts_lines_modified, "$line\n";
	}
	
	
	# Write the modified contents to the file
	if (open FILE, ">", "$known_hosts_path") {
		print FILE @known_hosts_lines_modified;
		close FILE;
		notify($ERRORS{'DEBUG'}, 0, "removed lines from $known_hosts_path matching $computer_short_name or $computer_private_ip_address");
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unable to open file for writing: $known_hosts_path");
		return;
	}
	
	# Run ssh-keyscan
	run_command("ssh-keyscan -t rsa '$computer_short_name' '$computer_private_ip_address' 2>&1 | grep -v '^#' >> $known_hosts_path");
	
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 update_public_ip_address

 Parameters  : none
 Returns     : If successful: true
               If failed: false
 Description : Checks the IP configuration mode for the management node -
               dynamic DHCP, manual DHCP, or static.  If DHCP is used, the
               public IP address is retrieved from the computer and the IP
               address in the computer table is updated if necessary.  If
               static public IP addresses are used, the computer is configured
               to use the public IP address stored in the computer table.

=cut

sub update_public_ip_address {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	my $reservation_id = $self->data->get_reservation_id() || return;
	my $computer_id = $self->data->get_computer_id() || return;
	my $computer_node_name = $self->data->get_computer_node_name() || return;
	my $image_os_name = $self->data->get_image_os_name() || return;
	my $image_os_type = $self->data->get_image_os_type() || return;
	my $computer_ip_address = $self->data->get_computer_ip_address();
	my $public_ip_configuration = $self->data->get_management_node_public_ip_configuration() || return;
	
	if ($public_ip_configuration =~ /dhcp/i) {
		notify($ERRORS{'DEBUG'}, 0, "IP configuration is set to $public_ip_configuration, attempting to retrieve dynamic public IP address from $computer_node_name");
		
		my $public_ip_address;
		
		# Try to retrieve the public IP address from the OS module
		if (!$self->can("get_public_ip_address")) {
			notify($ERRORS{'WARNING'}, 0, "unable to retrieve public IP address from $computer_node_name, OS module " . ref($self) . " does not implement a 'get_public_ip_address' subroutine");
			return;
		}
		elsif ($public_ip_address = $self->get_public_ip_address()) {
			notify($ERRORS{'DEBUG'}, 0, "retrieved public IP address from $computer_node_name using the OS module: $public_ip_address");
		}
		else {
			notify($ERRORS{'WARNING'}, 0, "failed to retrieve dynamic public IP address from $computer_node_name");
			insertloadlog($reservation_id, $computer_id, "dynamicDHCPaddress", "failed to retrieve dynamic public IP address from $computer_node_name");
			return;
		}
		
		# Update the computer table if the retrieved IP address does not match what is in the database
		if ($computer_ip_address ne $public_ip_address) {
			if (update_computer_address($computer_id, $public_ip_address)) {
				notify($ERRORS{'OK'}, 0, "updated dynamic public IP address in computer table for $computer_node_name, $public_ip_address");
				insertloadlog($reservation_id, $computer_id, "dynamicDHCPaddress", "updated dynamic public IP address in computer table for $computer_node_name, $public_ip_address");
			}
			else {
				notify($ERRORS{'WARNING'}, 0, "failed to update dynamic public IP address in computer table for $computer_node_name, $public_ip_address");
				insertloadlog($reservation_id, $computer_id, "dynamicDHCPaddress", "failed to update dynamic public IP address in computer table for $computer_node_name, $public_ip_address");
				return;
			}
		}
		else {
			notify($ERRORS{'DEBUG'}, 0, "public IP address in computer table is already correct for $computer_node_name: $computer_ip_address");
		}
		
	}
	
	elsif ($public_ip_configuration =~ /static/i) {
		notify($ERRORS{'DEBUG'}, 0, "IP configuration is set to $public_ip_configuration, attempting to set public IP address");
		
		# Try to set the static public IP address using the OS module
		if ($self->can("set_static_public_address") && $self->set_static_public_address()) {
			notify($ERRORS{'DEBUG'}, 0, "set static public IP address on $computer_node_name using OS module's set_static_public_address() method");
		}
		else {
			# Unable to set the static address using the OS module, try using utils.pm
			if (setstaticaddress($computer_node_name, $image_os_name, $computer_ip_address, $image_os_type)) {
				notify($ERRORS{'DEBUG'}, 0, "set static public IP address on $computer_node_name using utils.pm::setstaticaddress()");
			}
			else {
				notify($ERRORS{'WARNING'}, 0, "failed to set static public IP address on $computer_node_name");
				insertloadlog($reservation_id, $computer_id, "staticIPaddress", "failed to set static public IP address on $computer_node_name");
				return;
			}
		}
		insertloadlog($reservation_id, $computer_id, "staticIPaddress", "set static public IP address on $computer_node_name");
	}
	
	else {
		notify($ERRORS{'DEBUG'}, 0, "IP configuration is set to $public_ip_configuration, no public IP address updates necessary");
	}
	
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_vcld_post_load_status

 Parameters  : None
 Returns     : If vcld_post_load line exists: 1
               If vcld_post_load line exists: 0
               If an error occurred: undefined
 Description : Checks the currentimage.txt file on the computer for a line
               beginning with 'vcld_post_load='. Returns 1 if this line is found
               indicating that the OS module's post_load tasks have successfully
               run. Returns 0 if the line is not found, and undefined if an
               error occurred.

=cut

sub get_vcld_post_load_status {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Make sure the OS module implements a post load subroutine
	if (!$self->can('post_load')) {
		notify($ERRORS{'DEBUG'}, 0, "OS module " . ref($self) . " does not implement a post_load subroutine, returning 1");
		return 1;
	}
	
	my $management_node_keys = $self->data->get_management_node_keys();
	my $computer_node_name   = $self->data->get_computer_node_name();
	
	# Add a line to the end of currentimage.txt
	my $command = "grep vcld_post_load= currentimage.txt";
	
	my ($exit_status, $output) = run_ssh_command($computer_node_name, $management_node_keys, $command, '', '', 0);
	if (defined($output)) {
		if (my ($status_line) = grep(/vcld_post_load=/, @$output)) {
			notify($ERRORS{'DEBUG'}, 0, "vcld post load tasks have run on $computer_node_name: $status_line");
			return 1;
		}
		else {
			notify($ERRORS{'DEBUG'}, 0, "vcld post load tasks have NOT run on $computer_node_name");
			return 0;
		}
	}
	elsif ($exit_status) {
		notify($ERRORS{'WARNING'}, 0, "failed to retrieve vcld_post_load status line from currentimage.txt on $computer_node_name, exit status: $exit_status, output:\n" . join("\n", @$output));
		return;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to run SSH command to retrieve vcld_post_load status line from currentimage.txt on $computer_node_name");
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 set_vcld_post_load_status

 Parameters  : none
 Returns     : boolean
 Description : Adds a line to currentimage.txt indicating the vcld OS post_load
               tasks have run. The format of the line added is:
               vcld_post_load=success (<time>)
               
               This line is checked when a computer is reserved to make sure the
               post_load tasks have run. A computer may be loaded but the
               post_load tasks may not run if it is loaded manually or by some
               other means not controlled by vcld.

=cut

sub set_vcld_post_load_status {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $image_os_type = $self->data->get_image_os_type();
	my $management_node_keys = $self->data->get_management_node_keys();
	my $computer_node_name   = $self->data->get_computer_node_name();
	
	my $time = localtime;
	
	my $post_load_line = "vcld_post_load=success ($time)";
	
	# Assemble the command
	my $command;
	
	# Remove existing lines beginning with vcld_post_load
	$command .= "sed -i -e \'/vcld_post_load.*/d\' currentimage.txt";

	# Add a line to the end of currentimage.txt
	$command .= " && echo >> currentimage.txt";
	$command .= " && echo \"$post_load_line\" >> currentimage.txt";
	
	# Remove blank lines
	$command .= ' && sed -i -e \'/^[\\s\\r\\n]*$/d\' currentimage.txt';

	if ($image_os_type =~ /windows/i) {
		$command .= " && unix2dos currentimage.txt";
	}
	else {
		$command .= " && dos2unix currentimage.txt";
	}
	
	my ($exit_status, $output) = run_ssh_command($computer_node_name, $management_node_keys, $command, '', '', 1);
	if (defined($exit_status) && $exit_status == 0) {
		notify($ERRORS{'DEBUG'}, 0, "added line to currentimage.txt on $computer_node_name: '$post_load_line'");
	}
	elsif ($exit_status) {
		notify($ERRORS{'WARNING'}, 0, "failed to add line to currentimage.txt on $computer_node_name: '$post_load_line', exit status: $exit_status, output:\n" . join("\n", @$output));
		return;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to run SSH command to add line to currentimage.txt on $computer_node_name");
		return;
	}
	
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_private_interface_name

 Parameters  : none
 Returns     : string
 Description : Determines the private interface name based on the information in
               the network configuration hash returned by
               get_network_configuration. The interface which is assigned the
               private IP address for the reservation computer is returned.

=cut

sub get_private_interface_name {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the network configuration hash reference
	my $network_configuration = $self->get_network_configuration();
	if (!$network_configuration) {
		notify($ERRORS{'WARNING'}, 0, "unable to determine private interface name, failed to retrieve network configuration");
		return;
	}
	
	# Get the computer private IP address
	my $computer_private_ip_address = $self->data->get_computer_private_ip_address();
	if (!$computer_private_ip_address) {
		notify($ERRORS{'DEBUG'}, 0, "unable to retrieve computer private IP address from reservation data");
		return;
	}
	
	# Loop through all of the network interfaces found
	foreach my $interface_name (sort keys %$network_configuration) {
		# Get the interface IP addresses and make sure an IP address was found
		my @ip_addresses  = keys %{$network_configuration->{$interface_name}{ip_address}};
		if (!@ip_addresses) {
			notify($ERRORS{'DEBUG'}, 0, "interface is not assigned an IP address: $interface_name");
			next;
		}
		
		# Check if interface has the private IP address assigned to it
		if (grep { $_ eq $computer_private_ip_address } @ip_addresses) {
			notify($ERRORS{'DEBUG'}, 0, "determined private interface name: $interface_name (" . join (", ", @ip_addresses) . ")");
			return $interface_name;
		}
	}

	notify($ERRORS{'WARNING'}, 0, "failed to determined private interface name, no interface is assigned the private IP address for the reservation: $computer_private_ip_address\n" . format_data($network_configuration));
	return;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_public_interface_name

 Parameters  : none
 Returns     : string
 Description : Determines the public interface name based on the information in
               the network configuration hash returned by
               get_network_configuration.

=cut

sub get_public_interface_name {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the network configuration hash reference
	my $network_configuration = $self->get_network_configuration();
	if (!$network_configuration) {
		notify($ERRORS{'WARNING'}, 0, "unable to determine public interface name, failed to retrieve network configuration");
		return;
	}
	
	# Get the computer private IP address
	my $computer_private_ip_address = $self->data->get_computer_private_ip_address();
	if (!$computer_private_ip_address) {
		notify($ERRORS{'DEBUG'}, 0, "unable to retrieve computer private IP address from reservation data");
		return;
	}
	
	my $public_interface_name;
	
	# Loop through all of the network interfaces found
	foreach my $interface_name (sort keys %$network_configuration) {
		# Get the interface IP addresses and make sure an IP address was found
		my @ip_addresses  = keys %{$network_configuration->{$interface_name}{ip_address}};
		if (!@ip_addresses) {
			notify($ERRORS{'DEBUG'}, 0, "interface is not assigned an IP address: $interface_name");
			next;
		}
		
		# Check if interface has private IP address assigned to it
		if (grep { $_ eq $computer_private_ip_address } @ip_addresses) {
			notify($ERRORS{'DEBUG'}, 0, "ignoring private interface: $interface_name (" . join (", ", @ip_addresses) . ")");
			next;
		}
		
		my $description = $network_configuration->{$interface_name}{description} || '';
		
		# Check if the interface should be ignored based on the name or description
		if ($interface_name =~ /(^lo|loopback|vmnet|afs|tunnel|6to4|isatap|teredo)/i) {
			notify($ERRORS{'DEBUG'}, 0, "interface ignored because of name: $interface_name (" . join (", ", @ip_addresses) . ")");
			next;
		}
		elsif ($description =~ /loopback|virtual|afs|tunnel|pseudo|6to4|isatap/i) {
			notify($ERRORS{'DEBUG'}, 0, "interface ignored because of description: $interface_name, description: $description (" . join (", ", @ip_addresses) . ")");
			next;
		}
		
		# Loop through the IP addresses for the interface
		# Try to find a public address
		for my $ip_address (@ip_addresses) {
			
			if (is_public_ip_address($ip_address)) {
				notify($ERRORS{'DEBUG'}, 0, "determined public interface name: $interface_name (" . join (", ", @ip_addresses) . ")");
				return $interface_name;
			}
			else {
				notify($ERRORS{'DEBUG'}, 0, "found interface assigned a private address not matching private address for reservation: $interface_name (" . join(", ", @ip_addresses) . ")");
				
				if ($public_interface_name) {
					notify($ERRORS{'DEBUG'}, 0, "already found another interface with a private address not matching private address for reservation: $public_interface_name, the first one found will be used if an interface with a public address isn't found");
				}
				else {
					$public_interface_name = $interface_name;
					notify($ERRORS{'DEBUG'}, 0, "assuming interface is public if another interface with a public address isn't found: $public_interface_name");
				}
			}
		}
	}

	if ($public_interface_name) {
		notify($ERRORS{'DEBUG'}, 0, "did not find any interfaces assigned a public IP address, returning interface assigned a private IP address not matching the private IP address assigned to the reservation computer: $public_interface_name");
		return $public_interface_name;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to determine the public interface from the network configuration:\n" . format_data($network_configuration));
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

1;
__END__

=head1 SEE ALSO

L<http://cwiki.apache.org/VCL/>

=cut
