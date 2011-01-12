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

VCL::Module::Provisioning::VMware::vSphere_SDK;

=head1 SYNOPSIS

 my $vmhost_datastructure = $self->get_vmhost_datastructure();
 my $vsphere_sdk = VCL::Module::Provisioning::VMware::vSphere_SDK->new({data_structure => $vmhost_datastructure});
 my @registered_vms = $vsphere_sdk->get_registered_vms();

=head1 DESCRIPTION

 This module provides support for the vSphere SDK. The vSphere SDK can be used
 to manage VMware Server 2.x, ESX 3.0.x, ESX/ESXi 3.5, ESX/ESXi 4.0, vCenter
 Server 2.5, and vCenter Server 4.0.

=cut

##############################################################################
package VCL::Module::Provisioning::VMware::vSphere_SDK;

# Specify the lib path using FindBin
use FindBin;
use lib "$FindBin::Bin/../../../..";

# Configure inheritance
use base qw(VCL::Module::Provisioning::VMware::VMware);

# Specify the version of this module
our $VERSION = '2.00';

# Specify the version of Perl to use
use 5.008000;

use strict;
use warnings;
use diagnostics;
use English qw( -no_match_vars );
use File::Temp qw( tempdir );
use List::Util qw( max );

use VCL::utils;

##############################################################################

=head1 API OBJECT METHODS

=cut

#/////////////////////////////////////////////////////////////////////////////

=head2 get_registered_vms

 Parameters  : none
 Returns     : array
 Description : Returns an array containing the vmx file paths of the VMs running
               on the VM host.

=cut

sub get_registered_vms {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Override the die handler
	local $SIG{__DIE__} = sub{};
	
	my @vms;
	eval { @vms = @{Vim::find_entity_views(view_type => 'VirtualMachine')}; };
	
	my @vmx_paths;
	for my $vm (@vms) {
		push @vmx_paths, $self->_get_normal_path($vm->summary->config->vmPathName) || return;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "found " . scalar(@vmx_paths) . " registered VMs:\n" . join("\n", @vmx_paths));
	return @vmx_paths;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 vm_register

 Parameters  : $vmx_file_path
 Returns     : boolean
 Description : Registers the VM specified by vmx file path argument. Returns
               true if the VM is already registered or if the VM was
               successfully registered.

=cut

sub vm_register {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmx path argument and convert it to a datastore path
	my $vmx_path = $self->_get_datastore_path(shift) || return;
	
	my $host_view = VIExt::get_host_view(1) || return;
	my $datacenter = Vim::find_entity_view (view_type => 'Datacenter') || return;
	my $vm_folder = Vim::get_view(mo_ref => $datacenter->{vmFolder}) || return;
   my $resource_pool = Vim::find_entity_view(view_type => 'ResourcePool') || return;
   
	# Override the die handler because fileManager may call it
	local $SIG{__DIE__} = sub{};
	
	my $vm_mo_ref;
   eval { $vm_mo_ref = $vm_folder->RegisterVM(path => $vmx_path,
											  asTemplate => 'false',
											  pool => $resource_pool,
											  host => $host_view);
   };
	
	if ($@) {
		if ($@->isa('SoapFault') && ref($@->detail) eq 'AlreadyExists') {
			notify($ERRORS{'DEBUG'}, 0, "VM is already registered: $vmx_path");
			return 1;
		}
		else {
			notify($ERRORS{'WARNING'}, 0, "failed to register VM: $vmx_path, error:\n$@");
			return;
		}
	}
	
	if (ref($vm_mo_ref) ne 'ManagedObjectReference' || $vm_mo_ref->type ne 'VirtualMachine') {
		notify($ERRORS{'WARNING'}, 0, "RegisterVM did not return a VirtualMachine ManagedObjectReference:\n" . format_data($vm_mo_ref));
		return;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "registered VM: $vmx_path");
}

#/////////////////////////////////////////////////////////////////////////////

=head2 vm_unregister

 Parameters  : $vmx_file_path
 Returns     : boolean
 Description : Unregisters the VM specified by vmx file path argument. Returns
               true if the VM is not registered or if the VM was successfully
               unregistered.

=cut

sub vm_unregister {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmx path argument and convert it to a datastore path
	my $vmx_path = $self->_get_datastore_path(shift) || return;
	
	# Override the die handler
	local $SIG{__DIE__} = sub{};
	
   my $vm;
	eval { $vm = Vim::find_entity_view(view_type => 'VirtualMachine', filter => {'config.files.vmPathName' => $vmx_path}); };
	if (!$vm) {
		notify($ERRORS{'DEBUG'}, 0, "VM is not registered: $vmx_path");
		return 1;
   }
	
	# Make sure the VM is powered off or unregister will fail
	$self->vm_power_off($vmx_path) || return;

	eval { $vm->UnregisterVM(); };
	if ($@) {
		notify($ERRORS{'WARNING'}, 0, "failed to unregister vmx path: $vmx_path, error:\n$@");
		return;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "unregistered VM: $vmx_path");
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 vm_power_on

 Parameters  : $vmx_file_path
 Returns     : boolean
 Description : Powers on the VM specified by vmx file path argument. Returns
               true if the VM was successfully powered on or if it was already
               powered on.

=cut

sub vm_power_on {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmx path argument and convert it to a datastore path
	my $vmx_path = $self->_get_datastore_path(shift) || return;
	
	# Override the die handler
	local $SIG{__DIE__} = sub{};
	
	my $vm;
	eval { $vm = Vim::find_entity_view(view_type => 'VirtualMachine', filter => {'config.files.vmPathName' => $vmx_path}); };
	if (!$vm) {
		notify($ERRORS{'WARNING'}, 0, "unable to power on VM because it is not registered: $vmx_path");
		return;
   }
	
	eval { $vm->PowerOnVM(); };
	if ($@) {
		if ($@->isa('SoapFault') && ref($@->detail) eq 'InvalidPowerState') {
			my $existing_power_state = $@->detail->existingState->val;
			if ($existing_power_state =~ /on/i) {
				notify($ERRORS{'DEBUG'}, 0, "VM is already powered on: $vmx_path");
				return 1;
			}
		}
		
		notify($ERRORS{'WARNING'}, 0, "failed to power on VM: $vmx_path, error:\n$@");
		return;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "powered on VM: $vmx_path");
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 vm_power_off

 Parameters  : $vmx_file_path
 Returns     : boolean
 Description : Powers off the VM specified by vmx file path argument. Returns
               true if the VM was successfully powered off or if it was already
               powered off.

=cut

sub vm_power_off {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmx path argument and convert it to a datastore path
	my $vmx_path = $self->_get_datastore_path(shift) || return;
	
	# Override the die handler because fileManager may call it
	local $SIG{__DIE__} = sub{};
	
	my $vm;
	eval { $vm = Vim::find_entity_view(view_type => 'VirtualMachine', filter => {'config.files.vmPathName' => $vmx_path}); };
	if (!$vm) {
		notify($ERRORS{'WARNING'}, 0, "unable to power off VM because it is not registered: $vmx_path");
		return;
   }
	
	eval { $vm->PowerOffVM(); };
	if ($@) {
		if ($@->isa('SoapFault') && ref($@->detail) eq 'InvalidPowerState') {
			my $existing_power_state = $@->detail->existingState->val;
			if ($existing_power_state =~ /off/i) {
				notify($ERRORS{'DEBUG'}, 0, "VM is already powered off: $vmx_path");
				return 1;
			}
		}
		
		notify($ERRORS{'WARNING'}, 0, "failed to power off VM: $vmx_path, error:\n$@");
		return;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "powered off VM: $vmx_path");
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_vm_power_state

 Parameters  : $vmx_file_path
 Returns     : string
 Description : Determines the power state of the VM specified by the vmx file
               path argument. A string is returned containing one of the
               following values:
               -on
               -off
               -suspended

=cut

sub get_vm_power_state {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmx path argument and convert it to a datastore path
	my $vmx_path = $self->_get_datastore_path(shift) || return;
	
	# Override the die handler because fileManager may call it
	local $SIG{__DIE__} = sub{};
	
	my $vm;
	eval { $vm = Vim::find_entity_view(view_type => 'VirtualMachine', filter => {'config.files.vmPathName' => $vmx_path}); };
	if (!$vm) {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve power state of VM because it is not registered: $vmx_path");
		return;
   }
	
	my $power_state = $vm->runtime->powerState->val;
	my $return_power_state;
	if ($power_state =~ /on/i) {
		$return_power_state = 'on';
	}
	elsif ($power_state =~ /off/i) {
		$return_power_state = 'off';
	}
	elsif ($power_state =~ /suspended/i) {
		$return_power_state = 'suspended';
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "detected unsupported power state: $power_state");
		$return_power_state = '$power_state';
	}
	
	notify($ERRORS{'DEBUG'}, 0, "power state of VM $vmx_path: $return_power_state");
	return $return_power_state;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 copy_virtual_disk

 Parameters  : $source_vmdk_file_path, $destination_vmdk_file_path, $disk_type (optional), $adapter_type (optional)
 Returns     : boolean
 Description : Copies a virtual disk (set of vmdk files). This subroutine allows
               a virtual disk to be converted to a different disk type or
               adapter type. The source and destination vmdk file path arguments
               are required.
               
               The disk type argument is optional and may be one of the
               following values:
               -eagerZeroedThick
                  -all space allocated and wiped clean of any previous contents on the physical media at creation time
                  -may take longer time during creation compared to other disk formats
               -flatMonolithic
                  -preallocated monolithic disk
                  -disks in this format can be used with other VMware products
                  -format is only applicable as a destination format in a clone operation
                  -not usable for disk creation
                  -since vSphere API 4.0
               -preallocated
                  -all space allocated at creation time
                  -space is zeroed on demand as the space is used
               -raw
                  -raw device
               -rdm
                  -virtual compatibility mode raw disk mapping
                  -grants access to the entire raw disk and the virtual disk can participate in snapshots
               -rdmp
                  -physical compatibility mode (pass-through) raw disk mapping
                  -passes SCSI commands directly to the hardware
                  -cannot participate in snapshots
               -sparse2Gb, 2Gbsparse
                  -sparse disk with 2GB maximum extent size
                  -can be used with other VMware products
                  -2GB extent size makes these disks easier to burn to dvd or use on filesystems that don't support large files
                  -only applicable as a destination format in a clone operation
                  -not usable for disk creation
               -sparseMonolithic
                  -sparse monolithic disk
                  -can be used with other VMware products
                  -only applicable as a destination format in a clone operation
                  -not usable for disk creation
                  -since vSphere API 4.0
               -thick
                  -all space allocated at creation time
                  -space may contain stale data on the physical media
                  -primarily used for virtual machine clustering
                  -generally insecure and should not be used
                  -due to better performance and security properties, the use of the 'preallocated' format is preferred over this format
               -thick2Gb
                  -thick disk with 2GB maximum extent size
                  -can be used with other VMware products
                  -2GB extent size makes these disks easier to burn to dvd or use on filesystems that don't support large files
                  -only applicable as a destination format in a clone operation
                  -not usable for disk creation
               -thin (default)
                  -space required for thin-provisioned virtual disk is allocated and zeroed on demand as the space is used
                  
               The adapter type argument is optional and may be one of the
               following values:
               -busLogic
               -ide
               -lsiLogic
               
               If the adapter type argument is not specified an attempt will be
               made to retrieve it from the source vmdk file. If this fails,
               lsiLogic will be used.

=cut

sub copy_virtual_disk {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the source and destination path arguments in the datastore path format
	my $source_path = $self->_get_datastore_path(shift) || return;
	my $destination_path = $self->_get_datastore_path(shift) || return;
	
	# Get the adapter type and disk type arguments if they were specified
	# If not specified, set the default values
	my $destination_disk_type = shift || 'thin';
	
	# Fix the disk type in case 2gbsparse was passed
	if ($destination_disk_type =~ /2gbsparse/i) {
		$destination_disk_type = 'sparse2Gb';
	}
	
	# Check the disk type argument, the string must match exactly or the copy will fail
	my @valid_disk_types = qw( eagerZeroedThick flatMonolithic preallocated raw rdm rdmp sparse2Gb sparseMonolithic thick thick2Gb thin );
	if (!grep(/^$destination_disk_type$/, @valid_disk_types)) {
		notify($ERRORS{'WARNING'}, 0, "disk type argument is not valid: '$destination_disk_type', it must exactly match (case sensitive) one of the following strings:\n" . join("\n", @valid_disk_types));
		return;
	}
	
	my $destination_adapter_type = shift;
	
	# If the adapter type was not specified, retrieve it from the source vmdk file
	if (!$destination_adapter_type) {
		$destination_adapter_type = $self->get_virtual_disk_controller_type($source_path);
		if (!$destination_adapter_type) {
			notify($ERRORS{'WARNING'}, 0, "destination adapter type argument was not specifed and unable to retrieve adapter type from source vmdk file: $source_path, using lsiLogic");
			$destination_adapter_type = 'lsiLogic';
		}
	}
	
	# Check the adapter type argument, the string must match exactly or the copy will fail
	my @valid_adapter_types = qw( busLogic lsiLogic ide );
	if (!grep(/^$destination_adapter_type$/, @valid_adapter_types)) {
		notify($ERRORS{'WARNING'}, 0, "adapter type argument is not valid: '$destination_adapter_type', it must exactly match (case sensitive) one of the following strings:\n" . join("\n", @valid_adapter_types));
		return;
	}
	
	# Get a virtual disk manager object
	my $service_content = Vim::get_service_content() || return;
	if (!$service_content->{virtualDiskManager}) {
		notify($ERRORS{'WARNING'}, 0, "unable to copy virtual disk, virtual disk manager is not available through the vSphere SDK");
		return;
	}
	my $virtual_disk_manager = Vim::get_view(mo_ref => $service_content->{virtualDiskManager}) || return;
	
	# Get the destination partent directory path and create the directory
	my $destination_directory_path = $self->_get_parent_directory_datastore_path($destination_path) || return;
	$self->create_directory($destination_directory_path) || return;
	
	# Create a virtual disk spec object
	my $virtual_disk_spec = VirtualDiskSpec->new(adapterType => $destination_adapter_type,
																diskType => $destination_disk_type,
	);
	
	# Get the source vmdk file info so the source adapter and disk type can be displayed
	my $source_info = $self->_get_file_info($source_path) || return;
	notify($ERRORS{'DEBUG'}, 0, "source file info:\n" . format_data($source_info));
	my @file_names = keys(%{$source_info});
	my $info_file_name = $file_names[0];
	
	my $source_adapter_type = $source_info->{$info_file_name}{controllerType};
	my $source_disk_type = $source_info->{$info_file_name}{diskType};
	my $source_file_size_bytes = $source_info->{$info_file_name}{fileSize};
	if ($source_adapter_type !~ /\w/ || $source_disk_type !~ /\w/ || $source_file_size_bytes !~ /\d/) {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve adapter type, disk type, and file size of source file: '$source_path', file info:\n" . format_data($source_info));
		return;
	}
	
	# Override the die handler
	local $SIG{__DIE__} = sub{};
	
	# Attempt to copy the file
	notify($ERRORS{'DEBUG'}, 0, "attempting to copy file: '$source_path' --> '$destination_path'
			 adapter type: $source_adapter_type --> $destination_adapter_type
			 disk type: $source_disk_type --> $destination_disk_type
			 source file size: " . format_number($source_file_size_bytes));
	
	my $start_time = time;
	eval { $virtual_disk_manager->CopyVirtualDisk(sourceName => $source_path,
																 destName => $destination_path,
																 destSpec => $virtual_disk_spec,
																 force => 1);
	};
	
	# Check if an error occurred
	if (my $fault = $@) {
		notify($ERRORS{'WARNING'}, 0, "failed to copy vmdk: '$source_path' --> '$destination_path'\nerror:\n$fault");
		return;
	}
	
	notify($ERRORS{'OK'}, 0, "copied vmdk: '$source_path' --> '$destination_path'");
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 move_virtual_disk

 Parameters  : $source_path, $destination_path
 Returns     : boolean
 Description : Moves or renames a virtual disk (set of vmdk files).

=cut

sub move_virtual_disk {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the source path argument in datastore path format
	my $source_path = $self->_get_datastore_path(shift) || return;
	my $destination_path = $self->_get_datastore_path(shift) || return;
	
	# Make sure the source path ends with .vmdk
	if ($source_path !~ /\.vmdk$/i || $destination_path !~ /\.vmdk$/i) {
		notify($ERRORS{'WARNING'}, 0, "source and destination path arguments must end with .vmdk:\nsource path argument: $source_path\ndestination path argument: $destination_path");
		return;
	}
	
	# Make sure the source file exists
	if (!$self->file_exists($source_path)) {
		notify($ERRORS{'WARNING'}, 0, "source file does not exist: '$source_path'");
		return;
	}
	
	# Make sure the destination file does not exist
	if ($self->file_exists($destination_path)) {
		notify($ERRORS{'WARNING'}, 0, "destination file already exists: '$destination_path'");
		return;
	}
	
	# Get the destination parent directory path, make sure it exists
	my $destination_parent_directory_path = $self->_get_parent_directory_datastore_path($destination_path) || return;
	$self->create_directory($destination_parent_directory_path) || return;
	
	# Check if a virtual disk manager object is available
	my $service_content = Vim::get_service_content() || return;
	
	# Check if the virtual disk manager is available
	if (!$service_content->{virtualDiskManager}) {
		notify($ERRORS{'OK'}, 0, "unable to move virtual disk using vSphere SDK because virtual disk manager object is not available on the VM host");
		return 0;
	}
	
	# Create a virtual disk manager object
	my $virtual_disk_manager = Vim::get_view(mo_ref => $service_content->{virtualDiskManager});
	if (!$virtual_disk_manager) {
		notify($ERRORS{'WARNING'}, 0, "failed to create vSphere SDK virtual disk manager object");
		return;
	}
	
	# Create a datacenter object
	my $datacenter = Vim::find_entity_view(view_type => 'Datacenter');
	if (!$datacenter) {
		notify($ERRORS{'WARNING'}, 0, "failed to create vSphere SDK datacenter object");
		return;
	}
	
	# Override the die handler
	local $SIG{__DIE__} = sub{};
	
	# Attempt to move the virtual disk using MoveVirtualDisk
	notify($ERRORS{'DEBUG'}, 0, "attempting to move virtual disk: '$source_path' --> '$destination_path'");
	eval { $virtual_disk_manager->MoveVirtualDisk(sourceName => $source_path,
																 sourceDatacenter => $datacenter,
																 destName => $destination_path,
																 destDatacenter => $datacenter,
																 force => 0);
	};
	
	# Check if an error occurred
	if (my $fault = $@) {
		# Get the source file info
		my $source_file_info = $self->_get_file_info($source_path)->{$source_path};
		
		# A FileNotFound fault will be generated if the source vmdk file exists but there is a problem with it
		if ($fault->isa('SoapFault') && ref($fault->detail) eq 'FileNotFound' && defined($source_file_info->{type}) && $source_file_info->{type} !~ /vmdisk/i) {
			notify($ERRORS{'WARNING'}, 0, "failed to move virtual disk, source file is either not a virtual disk file or there is a problem with its configuration, check the 'Extent description' section of the vmdk file: '$source_path'\nsource file info:\n" . format_data($source_file_info));
		}
		elsif ($source_file_info) {
			notify($ERRORS{'WARNING'}, 0, "failed to move virtual disk:\n'$source_path' --> '$destination_path'\nsource file info:\n" . format_data($source_file_info) . "\n$fault");
		}
		else {
			notify($ERRORS{'WARNING'}, 0, "failed to move virtual disk:\n'$source_path' --> '$destination_path'\nsource file info: unavailable\n$fault");
		}
		
		return;
	}
	
	notify($ERRORS{'OK'}, 0, "moved virtual disk:\n'$source_path' --> '$destination_path'");
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 set_file_permissions

 Parameters  : 
 Returns     : boolean
 Description : 

=cut

sub set_file_permissions {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	# 
	my $service_content = Vim::get_service_content() || return;
	if (!$service_content->{authorizationManager}) {
		notify($ERRORS{'WARNING'}, 0, "unable to set file permissions, authorization manager is not available through the vSphere SDK");
		return;
	}
	my $authorization_manager = Vim::get_view(mo_ref => $service_content->{authorizationManager}) || return;
	notify($ERRORS{'DEBUG'}, 0, "created vSphere SDK authorization manager object");
	
	my $permissions = $authorization_manager->RetrieveEntityPermissions();

}

#/////////////////////////////////////////////////////////////////////////////

=head2 create_nfs_datastore

 Parameters  : $datastore_name, $remote_host, $remote_path
 Returns     : boolean
 Description : Creates an NFS datastore on the VM host. Note: this subroutine is
               not currenly being called by anything.

=cut

sub create_nfs_datastore {
	my $self = shift;
	if (ref($self) !~ /module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the arguments
	my ($datastore_name, $remote_host, $remote_path) = @_;
	if (!$datastore_name || !$remote_host || !$remote_path) {
		notify($ERRORS{'WARNING'}, 0, "datastore name, remote host, and remote path arguments were not supplied");
		return;
	}
	
	# Remove trailing slashes from the remote path
	$remote_path =~ s/\/+$//g;
	
	# Assemble a datastore device string, used to check if existing datastore is pointing to the same remote host and path
	my $datastore_device = "$remote_host:$remote_path";
	
	# Get the existing datastore info
	my $datastore_info = $self->_get_datastore_info();
	for my $check_datastore_name (keys(%$datastore_info)) {
		my $check_datastore_type = $datastore_info->{$check_datastore_name}{type};
		
		# Make sure a non-NFS datastore with the same name doesn't alreay exist
		if ($check_datastore_type !~ /nfs/i) {
			if ($check_datastore_name eq $datastore_name) {
				notify($ERRORS{'WARNING'}, 0, "datastore named $datastore_name already exists on VM host but its type is not NFS:\n" . format_data($datastore_info->{$check_datastore_name}));
				return;
			}
			else {
				# Type isn't NFS and name doesn't match
				next;
			}
		}
		
		# Get the existing datastore device string, format is:
		# 10.25.0.245:/install/vmtest/datastore
		my $check_datastore_device = $datastore_info->{$check_datastore_name}{datastore}{value};
		if (!$check_datastore_device) {
			notify($ERRORS{'WARNING'}, 0, "unable to retrieve datastore device string from datastore info:\n" . format_data($datastore_info->{$check_datastore_name}));
			next;
		}
		
		# Remove trailing slashes from existing device string
		$check_datastore_device =~ s/\/+$//g;
		
		# Check if datastore already exists pointing to the same remote path
		if ($check_datastore_name eq $datastore_name) {
			# Datastore names match, check if existing datastore is pointing the the requested device path
			if ($check_datastore_device eq $datastore_device) {
				notify($ERRORS{'DEBUG'}, 0, "$check_datastore_type datastore '$datastore_name' already exists on VM host, remote path: $check_datastore_device");
				return 1;
			}
			else {
				notify($ERRORS{'WARNING'}, 0, "$check_datastore_type datastore '$datastore_name' already exists on VM host but it is pointing to a different remote path:
						 requested remote path: $datastore_device
						 existing remote path: $check_datastore_device");
				return;
			}
		}
		else {
			# Datastore names don't match, make sure an existing datastore with a different name isn't pointing to the requested device path
			if ($check_datastore_device eq $datastore_device) {
				notify($ERRORS{'WARNING'}, 0, "$check_datastore_type datastore with a different name already exists on VM host pointing to '$check_datastore_device':
						 requested datastore name: $datastore_name
						 existing datastore name: $check_datastore_name");
				return;
			}
			else {
				# Datastore name doesn't match, datastore remote path doesn't match
				next;
			}
		}
	}
	
	# Get the datastore system object
	my $datastore_system = Vim::get_view(mo_ref => VIExt::get_host_view(1)->configManager->datastoreSystem);
	if (!$datastore_system) {
		notify($ERRORS{'WARNING'}, 0, "failed to retrieve datastore system object");
		return;
	}
	
	# Create a HostNasVolumeSpec object to store the datastore configuration
	my $host_nas_volume_spec = HostNasVolumeSpec->new(accessMode => 'readWrite',
																	  localPath => $datastore_name,
																	  remoteHost => $remote_host,
																	  remotePath => $remote_path,
																	  );
	
	# Override the die handler
	local $SIG{__DIE__} = sub{};
	
	# Attempt to cretae the NAS datastore
	notify($ERRORS{'DEBUG'}, 0, "attempting to create NAS datastore:\n" . format_data($host_nas_volume_spec));
	eval { $datastore_system->CreateNasDatastore(spec => $host_nas_volume_spec); };
	if (my $fault = $@) {
		notify($ERRORS{'WARNING'}, 0, "failed to create NAS datastore on VM host:\ndatastore name: $datastore_name\nremote host: $remote_host\nremote path: $remote_path\nerror:\n$@");
		return;
	}
	
	notify($ERRORS{'OK'}, 0, "created NAS datastore on VM host: $datastore_name");
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_virtual_disk_controller_type

 Parameters  : $vmdk_file_path
 Returns     : string
 Description : Retrieves the disk controller type configured for the virtual
               disk specified by the vmdk file path argument. A string is
               returned containing one of the following values:
               -lsiLogic
               -busLogic
               -ide

=cut

sub get_virtual_disk_controller_type {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmdk file path argument
	my $vmdk_file_path = $self->_get_datastore_path(shift) || return;
	if ($vmdk_file_path !~ /\.vmdk$/) {
		notify($ERRORS{'WARNING'}, 0, "file path argument must end with .vmdk: $vmdk_file_path");
		return;
	}
	
	# Get the vmdk file info
	my $vmdk_file_info = $self->_get_file_info($vmdk_file_path)->{$vmdk_file_path};
	if (!$vmdk_file_info) {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve info for file: $vmdk_file_path");
		return;
	}
	
	# Check if the controllerType key exists in the vmdk file info
	if (!defined($vmdk_file_info->{controllerType}) || !$vmdk_file_info->{controllerType}) {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve controllerType value from file info: $vmdk_file_path\n" . format_data($vmdk_file_info));
		return;
	}
	
	my $controller_type = $vmdk_file_info->{controllerType};
	
	my $return_controller_type;
	if ($controller_type =~ /lsi/i) {
		$return_controller_type = 'lsiLogic';
	}
	elsif ($controller_type =~ /bus/i) {
		$return_controller_type = 'busLogic';
	}
	elsif ($controller_type =~ /ide/i) {
		$return_controller_type = 'ide';
	}
	else {
		$return_controller_type = $controller_type;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "retrieved controllerType value from vmdk file info: $return_controller_type ($controller_type)");
	return $return_controller_type;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_virtual_disk_type

 Parameters  : $vmdk_file_path
 Returns     : string
 Description : Retrieves the disk type configured for the virtual
               disk specified by the vmdk file path argument. A string is
               returned containing one of the following values:
               -FlatVer1
               -FlatVer2
               -RawDiskMappingVer1
               -SparseVer1
               -SparseVer2

=cut

sub get_virtual_disk_type {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmdk file path argument
	my $vmdk_file_path = $self->_get_datastore_path(shift) || return;
	if ($vmdk_file_path !~ /\.vmdk$/) {
		notify($ERRORS{'WARNING'}, 0, "file path argument must end with .vmdk: $vmdk_file_path");
		return;
	}
	
	# Get the vmdk file info
	my $vmdk_file_info = $self->_get_file_info($vmdk_file_path)->{$vmdk_file_path};
	if (!$vmdk_file_info) {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve info for file: $vmdk_file_path");
		return;
	}
	
	# Check if the diskType key exists in the vmdk file info
	if (!defined($vmdk_file_info->{diskType}) || !$vmdk_file_info->{diskType}) {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve diskType value from file info: $vmdk_file_path\n" . format_data($vmdk_file_info));
		return;
	}
	
	my $disk_type = $vmdk_file_info->{diskType};
	
	if ($disk_type =~ /VirtualDisk(.+)BackingInfo/) {
		$disk_type = $1;
	}
	notify($ERRORS{'DEBUG'}, 0, "retrieved diskType value from vmdk file info: $disk_type");
	return $disk_type;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_virtual_disk_hardware_version

 Parameters  : $vmdk_file_path
 Returns     : string
 Description : Retrieves the virtual disk hardware version configured for the
               virtual disk specified by the vmdk file path argument.

=cut

sub get_virtual_disk_hardware_version {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the vmdk file path argument
	my $vmdk_file_path = $self->_get_datastore_path(shift) || return;
	if ($vmdk_file_path !~ /\.vmdk$/) {
		notify($ERRORS{'WARNING'}, 0, "file path argument must end with .vmdk: $vmdk_file_path");
		return;
	}
	
	# Get the vmdk file info
	my $vmdk_file_info = $self->_get_file_info($vmdk_file_path)->{$vmdk_file_path};
	if (!$vmdk_file_info) {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve info for file: $vmdk_file_path");
		return;
	}
	
	# Check if the hardwareVersion key exists in the vmdk file info
	my $hardware_version = $vmdk_file_info->{hardwareVersion};
	if (!$hardware_version) {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve hardwareVersion value from file info: $vmdk_file_path\n" . format_data($vmdk_file_info));
		return;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "retrieved hardwareVersion value from vmdk file info: $hardware_version");
	return $hardware_version;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_vmware_product_name

 Parameters  : none
 Returns     : string
 Description : Returns the full VMware product name installed on the VM host.
               Examples:
					VMware Server 2.0.2 build-203138
					VMware ESXi 4.0.0 build-208167

=cut

sub get_vmware_product_name {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	return $self->{product_name} if $self->{product_name};
	
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	
	# Get the host view
	my $host_view = VIExt::get_host_view(1);
	my $product_name = $host_view->config->product->fullName;
	
	if ($product_name) {
		notify($ERRORS{'DEBUG'}, 0, "VMware product being used on VM host $vmhost_hostname: '$product_name'");
		$self->{product_name} = $product_name;
		return $self->{product_name};
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve VMware product name being used on VM host $vmhost_hostname");
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_vmware_product_version

 Parameters  : none
 Returns     : string
 Description : Returns the VMware product version installed on the VM host.
               Example: '4.0.0'

=cut

sub get_vmware_product_version {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	return $self->{product_version} if $self->{product_version};
	
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	
	# Get the host view
	my $host_view = VIExt::get_host_view(1);
	my $product_version = $host_view->config->product->version;
	
	if ($product_version) {
		notify($ERRORS{'DEBUG'}, 0, "retrieved product version for VM host $vmhost_hostname: $product_version");
		$self->{product_version} = $product_version;
		return $self->{product_version};
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve product version for VM host $vmhost_hostname");
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_network_names

 Parameters  : none
 Returns     : array
 Description : Retrieves the network names configured on the VM host.

=cut

sub get_network_names {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the host view
	my $host_view = VIExt::get_host_view(1);
	
	# Retrieve the network info, check if each network is accessible
	my @network_names;
	for my $network (@{Vim::get_views(mo_ref_array => $host_view->network)}) {
		push @network_names, $network->name;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "retrieved network names:\n" . join("\n", @network_names));
	return @network_names;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 is_restricted

 Parameters  : none
 Returns     : boolean
 Description : Determines if remote access to the VM host via the vSphere SDK is
               restricted due to the type of VMware license being used on the
               host. 0 is returned if remote access is not restricted. 1 is
               returned if remote access is restricted and the access to the VM
               host is read-only.

=cut

sub is_restricted {
	my $self = shift;
	if (ref($self) !~ /module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	my $service_content = Vim::get_service_content();
	if (!$service_content) {
		notify($ERRORS{'WARNING'}, 0, "unable to vSphere SDK service content object, assuming access to the VM host via the vSphere SDK is restricted");
		return 1;
	}
	
	# Attempt to get a virtual disk manager object
	# This is required to copy virtual disks and perform other operations
	if (!$service_content->{virtualDiskManager}) {
		notify($ERRORS{'OK'}, 0, "access to the VM host is restricted, virtual disk manager is not available through the vSphere SDK");
		return 1;
	}
	
	# Get a fileManager object
	my $file_manager = Vim::get_view(mo_ref => $service_content->{fileManager}) || return;
	if (!$file_manager) {
		notify($ERRORS{'WARNING'}, 0, "unable to determine if access to the VM host via the vSphere SDK is restricted due to the license, failed to retrieve file manager object");
		return 1;
	}
	
	# Override the die handler because MakeDirectory may call it
	local $SIG{__DIE__} = sub{};

	# Attempt to create the test directory, check if RestrictedVersion fault occurs
	eval { $file_manager->DeleteDatastoreFile(name => ''); } ;
	if (my $fault = $@) {
		if ($fault->isa('SoapFault') && ref($fault->detail) eq 'RestrictedVersion') {
			notify($ERRORS{'OK'}, 0, "access to the VM host via the vSphere SDK is restricted due to the license: " . $fault->name);
			return 1;
		}
		elsif ($fault->isa('SoapFault') && (ref($fault->detail) eq 'InvalidDatastorePath' || ref($fault->detail) eq 'InvalidArgument')) {
			# Do nothing, expected since empty path was passed to DeleteDatastoreFile
		}
		else {
			notify($ERRORS{'WARNING'}, 0, "failed to determine if access to the VM host via the vSphere SDK is restricted due to the license, error:\n$@");
			return 1;
		}
	}
	
	notify($ERRORS{'OK'}, 0, "access to the VM host via the vSphere SDK is NOT restricted due to the license");
	
	return 0;
}

##############################################################################

=head1 OS FUNCTIONALITY OBJECT METHODS

=cut

#/////////////////////////////////////////////////////////////////////////////

=head2 create_directory

 Parameters  : $directory_path
 Returns     : boolean
 Description : Creates a directory on a datastore on the VM host using the
               vSphere SDK.

=cut

sub create_directory {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get and check the directory path argument
	my $directory_path = $self->_get_datastore_path(shift) || return;
	
	# Check if the directory already exists
	return 1 if $self->file_exists($directory_path);
	
	# Get the VM host name
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	
	# Get a fileManager object
	my $service_content = Vim::get_service_content() || return;
	my $file_manager = Vim::get_view(mo_ref => $service_content->{fileManager}) || return;
	
	# Override the die handler because MakeDirectory may call it
	local $SIG{__DIE__} = sub{};

	# Attempt to create the directory
	eval { $file_manager->MakeDirectory(name => $directory_path,
													createParentDirectories => 1);
	};
	
	if ($@) {
		if ($@->isa('SoapFault') && ref($@->detail) eq 'FileAlreadyExists') {
			notify($ERRORS{'DEBUG'}, 0, "directory already exists: '$directory_path'");
			return 1;
		}
		else {
			notify($ERRORS{'WARNING'}, 0, "failed to create directory: '$directory_path'\nerror:\n$@");
			return;
		}
	}
	else {
		notify($ERRORS{'OK'}, 0, "created directory: '$directory_path'");
		return 1;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 delete_file

 Parameters  : $file_path
 Returns     : boolean
 Description : Deletes the file from a datastore on the VM host. Wildcards may
               not be used in the file path argument.

=cut

sub delete_file {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get and check the file path argument
	my $path_argument = shift;
	if (!$path_argument) {
		notify($ERRORS{'WARNING'}, 0, "path argument was not specified");
		return;
	}
	
	my $datastore_path = $self->_get_datastore_path($path_argument);
	if (!$datastore_path) {
		notify($ERRORS{'WARNING'}, 0, "failed to convert path argument to datastore path: $path_argument");
		return;
	}
	
	# Sanity check, make sure the file path argument is not the root of a datastore
	# Otherwise everything in the datastore would be deleted
	if ($datastore_path =~ /^\[.+\]$/) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called with the file path argument pointing to the root of a datastore, this would cause all datastore contents to be deleted\nfile path argument: '$path_argument'\ndatastore path: '$datastore_path'");
		return;
	}
	
	# Get a fileManager object
	my $service_content = Vim::get_service_content() || return;
	my $file_manager = Vim::get_view(mo_ref => $service_content->{fileManager}) || return;
	
	# Override the die handler because fileManager may call it
	local $SIG{__DIE__} = sub{};

	# Attempt to delete the file
	notify($ERRORS{'OK'}, 0, "attempting to delete file: $datastore_path");
	eval { $file_manager->DeleteDatastoreFile(name => $datastore_path); };
	if ($@) {
		if ($@->isa('SoapFault') && ref($@->detail) eq 'FileNotFound') {
			notify($ERRORS{'DEBUG'}, 0, "file does not exist: $datastore_path");
			return 1;
		}
		else {
			notify($ERRORS{'WARNING'}, 0, "failed to delete file: $datastore_path, error:\n$@");
			return;
		}
	}
	else {
		notify($ERRORS{'OK'}, 0, "deleted file: $datastore_path");
		return 1;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 copy_file

 Parameters  : $source_file_path, $destination_file_path
 Returns     : boolean
 Description : Copies a file from one datastore location on the VM host to
               another datastore location on the VM host. Wildcards may not be
               used in the file path argument.

=cut

sub copy_file {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get and check the file path arguments
	my $source_file_path = $self->_get_datastore_path(shift) || return;
	my $destination_file_path = $self->_get_datastore_path(shift) || return;
	
	# Get the VM host name
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	
	# Get the destination directory path and create the directory if it doesn't exit
	my $destination_directory_path = $self->_get_parent_directory_datastore_path($destination_file_path) || return;
	$self->create_directory($destination_directory_path) || return;
	
	# Get a fileManager object
	my $service_content = Vim::get_service_content() || return;
	my $file_manager = Vim::get_view(mo_ref => $service_content->{fileManager}) || return;
	my $datacenter = Vim::find_entity_view(view_type => 'Datacenter') || return;
	
	# Override the die handler because fileManager may call it
	local $SIG{__DIE__} = sub{};
	
	# Attempt to copy the file
	notify($ERRORS{'DEBUG'}, 0, "attempting to copy file on VM host $vmhost_hostname: '$source_file_path' --> '$destination_file_path'");
	eval { $file_manager->CopyDatastoreFile(sourceName => $source_file_path,
														 sourceDatacenter => $datacenter,
														 destinationName => $destination_file_path,
														 destinationDatacenter => $datacenter,
														 force => 0);
	};
	
	# Check if an error occurred
	if ($@) {
		if ($@->isa('SoapFault') && ref($@->detail) eq 'FileNotFound') {
			notify($ERRORS{'WARNING'}, 0, "source file does not exist on VM host $vmhost_hostname: '$source_file_path'");
			return 0;
		}
		elsif ($@->isa('SoapFault') && ref($@->detail) eq 'FileAlreadyExists') {
			notify($ERRORS{'WARNING'}, 0, "destination file already exists on VM host $vmhost_hostname: '$destination_file_path'");
			return 0;
		}
		else {
			notify($ERRORS{'WARNING'}, 0, "failed to copy file on VM host $vmhost_hostname: '$source_file_path' --> '$destination_file_path'\nerror:\n$@");
			return;
		}
	}
	
	notify($ERRORS{'OK'}, 0, "copied file on VM host $vmhost_hostname: '$source_file_path' --> '$destination_file_path'");
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 copy_file_to

 Parameters  : $source_file_path, $destination_file_path
 Returns     : boolean
 Description : Copies a file from the management node to a datastore on the VM
               host. The complete source and destination file paths must be
               specified. Wildcards may not be used.

=cut

sub copy_file_to {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the source and destination arguments
	my $source_file_path = normalize_file_path(shift) || return;
	my $destination_file_path = $self->_get_datastore_path(shift) || return;
	
	# Make sure the source file exists on the management node
	if (!-f $source_file_path) {
		notify($ERRORS{'WARNING'}, 0, "source file does not exist on the management node: '$source_file_path'");
		return;
	}
	
	# Make sure the destination directory path exists
	my $destination_directory_path = $self->_get_parent_directory_datastore_path($destination_file_path) || return;
	$self->create_directory($destination_directory_path) || return;
	sleep 2;
	
	# Get the VM host name
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	
	# Get the destination datastore name and relative datastore path
	my $destination_datastore_name = $self->_get_datastore_name($destination_file_path);
	my $destination_relative_datastore_path = $self->_get_relative_datastore_path($destination_file_path);
	
	# Override the die handler
	local $SIG{__DIE__} = sub{};
	
	# Attempt to copy the file
	notify($ERRORS{'DEBUG'}, 0, "attempting to copy file from management node to VM host: '$source_file_path' --> $vmhost_hostname:'[$destination_datastore_name] $destination_relative_datastore_path'");
	my $response;
	eval { $response = VIExt::http_put_file("folder" , $source_file_path, $destination_relative_datastore_path, $destination_datastore_name, "ha-datacenter"); };
	if ($response->is_success) {
		notify($ERRORS{'DEBUG'}, 0, "copied file from management node to VM host: '$source_file_path' --> $vmhost_hostname:'[$destination_datastore_name] $destination_relative_datastore_path'");
		return 1;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to copy file from management node to VM host: '$source_file_path' --> $vmhost_hostname:'$destination_file_path'\nerror: " . $response->message);
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 copy_file_from

 Parameters  : $source_file_path, $destination_file_path
 Returns     : boolean
 Description : Copies file from a datastore on the VM host to the management
               node. The complete source and destination file paths must be
               specified. Wildcards may not be used.

=cut

sub copy_file_from {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the source and destination arguments
	my $source_file_path = $self->_get_datastore_path(shift) || return;
	my $destination_file_path = normalize_file_path(shift) || return;
	
	# Get the destination directory path and make sure the directory exists
	my $destination_directory_path = $self->_get_parent_directory_normal_path($destination_file_path) || return;
	if (!-d $destination_directory_path) {
		# Attempt to create the directory
		my $command = "mkdir -p -v \"$destination_directory_path\" 2>&1 && ls -1d \"$destination_directory_path\"";
		my ($exit_status, $output) = run_command($command, 1);
		if (!defined($output)) {
			notify($ERRORS{'WARNING'}, 0, "failed to run command to create directory on management node: '$destination_directory_path'\ncommand: '$command'");
			return;
		}
		elsif (grep(/created directory/i, @$output)) {
			notify($ERRORS{'OK'}, 0, "created directory on management node: '$destination_directory_path'");
		}
		elsif (grep(/mkdir: /i, @$output)) {
			notify($ERRORS{'WARNING'}, 0, "error occurred attempting to create directory on management node: '$destination_directory_path':\ncommand: '$command'\nexit status: $exit_status\noutput:\n" . join("\n", @$output));
			return;
		}
		elsif (grep(/^$destination_directory_path/, @$output)) {
			notify($ERRORS{'OK'}, 0, "directory already exists on management node: '$destination_directory_path'");
		}
		else {
			notify($ERRORS{'WARNING'}, 0, "unexpected output returned from command to create directory on management node: '$destination_directory_path':\ncommand: '$command'\nexit status: $exit_status\noutput:\n" . join("\n", @$output));
			return;
		}
	}
	
	# Get the VM host name
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	
	# Get the source datastore name
	my $source_datastore_name = $self->_get_datastore_name($source_file_path) || return;
	
	# Get the source file relative datastore path
	my $source_file_relative_datastore_path = $self->_get_relative_datastore_path($source_file_path) || return;
	
	# Override the die handler
	local $SIG{__DIE__} = sub{};
	
	# Attempt to copy the file
	notify($ERRORS{'DEBUG'}, 0, "attempting to copy file from VM host to management node: $vmhost_hostname:'[$source_datastore_name] $source_file_relative_datastore_path' --> '$destination_file_path'");
	my $response;
	eval { $response = VIExt::http_get_file("folder", $source_file_relative_datastore_path, $source_datastore_name, "ha-datacenter", $destination_file_path); };
	if ($response->is_success) {
		notify($ERRORS{'DEBUG'}, 0, "copied file from VM host to management node: $vmhost_hostname:'[$source_datastore_name] $source_file_relative_datastore_path' --> '$destination_file_path'");
		return 1;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to copy file from VM host to management node: $vmhost_hostname:'[$source_datastore_name] $source_file_relative_datastore_path' --> '$destination_file_path'\nerror: " . $response->message);
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_file_contents

 Parameters  : $file_path
 Returns     : array
 Description : Returns an array containing the contents of the file on the VM
               host specified by the file path argument. Each array element
               contains a line in the file.

=cut

sub get_file_contents {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# TODO: add file size check before retrieving file in case file is huge
	
	# Get the source and destination arguments
	my ($path) = shift;
	if (!$path) {
		notify($ERRORS{'WARNING'}, 0, "file path argument was not specified");
		return;
	}
	
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	
	# Create a temp directory to store the file and construct the temp file path
	# The temp directory is automatically deleted then this variable goes out of scope
	my $temp_directory_path = tempdir( CLEANUP => 1 );
	my $source_file_name = $self->_get_file_name($path);
	my $temp_file_path = "$temp_directory_path/$source_file_name";
	
	$self->copy_file_from($path, $temp_file_path) || return;
	
	# Run cat to retrieve the contents of the file
	my $command = "cat \"$temp_file_path\"";
	my ($exit_status, $output) = VCL::utils::run_command($command, 1);
	if (!defined($output)) {
		notify($ERRORS{'WARNING'}, 0, "failed to run command to read file: '$temp_file_path'\ncommand: '$command'");
		return;
	}
	elsif (grep(/^cat: /, @$output)) {
		notify($ERRORS{'WARNING'}, 0, "failed to read contents of file: '$temp_file_path', exit status: $exit_status, output:\n" . join("\n", @$output));
		return;
	}
	else {
		notify($ERRORS{'DEBUG'}, 0, "retrieved " . scalar(@$output) . " lines from file: '$temp_file_path'");
	}
	
	# Output lines contain trailing newlines, remove them
	@$output = map { chomp; $_; } @$output;
	return @$output;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 move_file

 Parameters  : $source_path, $destination_path
 Returns     : boolean
 Description : Moves or renames a file from one datastore location on the VM
               host to another datastore location on the VM host. Wildcards may
               not be used in the file path argument.

=cut

sub move_file {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get and check the file path arguments
	my $source_file_path = $self->_get_datastore_path(shift) || return;
	my $destination_file_path = $self->_get_datastore_path(shift) || return;
	
	# Get the VM host name
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	
	# Get the destination directory path and create the directory if it doesn't exit
	my $destination_directory_path = $self->_get_parent_directory_datastore_path($destination_file_path) || return;
	$self->create_directory($destination_directory_path) || return;
	
	# Get a fileManager and Datacenter object
	my $service_content = Vim::get_service_content() || return;
	my $file_manager = Vim::get_view(mo_ref => $service_content->{fileManager}) || return;
	my $datacenter = Vim::find_entity_view(view_type => 'Datacenter') || return;
	
	# Override the die handler because fileManager may call it
	local $SIG{__DIE__} = sub{};

	# Attempt to copy the file
	notify($ERRORS{'DEBUG'}, 0, "attempting to move file on VM host $vmhost_hostname: '$source_file_path' --> '$destination_file_path'");
	eval { $file_manager->MoveDatastoreFile(sourceName => $source_file_path,
														 sourceDatacenter => $datacenter,
														 destinationName => $destination_file_path,
														 destinationDatacenter => $datacenter
														 );
	};
	
	if ($@) {
		if ($@->isa('SoapFault') && ref($@->detail) eq 'FileNotFound') {
			notify($ERRORS{'WARNING'}, 0, "source file does not exist on VM host $vmhost_hostname: '$source_file_path'");
			return 0;
		}
		elsif ($@->isa('SoapFault') && ref($@->detail) eq 'FileAlreadyExists') {
			notify($ERRORS{'WARNING'}, 0, "destination file already exists on VM host $vmhost_hostname: '$destination_file_path'");
			return 0;
		}
		else {
			notify($ERRORS{'WARNING'}, 0, "failed to move file on VM host $vmhost_hostname: '$source_file_path' --> '$destination_file_path', error:\n$@");
			return;
		}
	}
	
	notify($ERRORS{'OK'}, 0, "moved file on VM host $vmhost_hostname: '$source_file_path' --> '$destination_file_path'");
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 file_exists

 Parameters  : $file_path
 Returns     : boolean
 Description : Determines if a file exists on a datastore on the VM host.

=cut

sub file_exists {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get and check the file path argument
	my $file_path = $self->_get_datastore_path(shift) || return;
	
	# Check if the path argument is the root of a datastore
	if ($file_path =~ /^\[(.+)\]$/) {
		my $datastore_name = $1;
		(my @datastore_names = $self->_get_datastore_names()) || return;
		
		if (grep(/^$datastore_name$/, @datastore_names)) {
			notify($ERRORS{'DEBUG'}, 0, "file (datastore root) exists: $file_path");
			return 1;
		}
		else {
			notify($ERRORS{'DEBUG'}, 0, "file (datastore root) does not exist: $file_path, datastores on VM host:\n" . join("\n", @datastore_names));
			return 0;
		}
	}
	
	# Take the path apart, get the filename and parent directory path
	my $base_directory_path = $self->_get_parent_directory_datastore_path($file_path) || return;
	my $file_name = $self->_get_file_name($file_path) || return;
	
	my $result = $self->find_files($base_directory_path, $file_name);
	if ($result) {
		notify($ERRORS{'DEBUG'}, 0, "file exists: $file_path");
		return 1;
	}
	elsif (defined($result)) {
		notify($ERRORS{'DEBUG'}, 0, "file does not exist: $file_path");
		return 0;
	}
	else {
		notify($ERRORS{'WARNING'}, 0, "failed to determine if file exists: $file_path");
		return;
	}
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_file_size

 Parameters  : $file_path
 Returns     : integer
 Description : Determines the size of a file of a datastore in bytes. Wildcards
               may be used in the file path argument. The total size of all
               files found will be returned. Subdirectories are not searched.

=cut

sub get_file_size {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get and check the file path argument
	my $file_path = shift;
	if (!$file_path) {
		notify($ERRORS{'WARNING'}, 0, "file path argument was not specified");
		return;
	}
	
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	
	# Get the file info
	my $file_info = $self->_get_file_info($file_path);
	if (!defined($file_info)) {
		notify($ERRORS{'WARNING'}, 0, "unable to get file size, failed to get file info for: $file_path");
		return;
	}
	
	# Make sure the file info is not null or else an error occurred
	if (!$file_info) {
		notify($ERRORS{'WARNING'}, 0, "unable to retrieve info for file on $vmhost_hostname: $file_path");
		return;
	}
	
	# Check if there are any keys in the file info hash - no keys indicates no files were found
	if (!keys(%{$file_info})) {
		notify($ERRORS{'DEBUG'}, 0, "unable to determine size of file on $vmhost_hostname because it does not exist: $file_path");
		return;
	}
	
	# Loop through the files, add their sizes to the total
	my $total_size_bytes = 0;
	for my $file_path (keys(%{$file_info})) {
		my $file_size_bytes = $file_info->{$file_path}{fileSize};
		notify($ERRORS{'DEBUG'}, 0, "size of '$file_path': " . format_number($file_size_bytes) . " bytes");
		$total_size_bytes += $file_size_bytes;
	}
	
	my $total_size_bytes_string = format_number($total_size_bytes);
	my $total_size_mb_string = format_number(($total_size_bytes / 1024 / 1024), 2);
	my $total_size_gb_string = format_number(($total_size_bytes / 1024 / 1024 /1024), 2);
	
	notify($ERRORS{'DEBUG'}, 0, "total file size of '$file_path': $total_size_bytes_string bytes ($total_size_mb_string MB, $total_size_gb_string GB)");
	return $total_size_bytes;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 find_files

 Parameters  : $base_directory_path, $search_pattern, $search_subdirectories (optional)
 Returns     : array
 Description : Finds files in a datastore on the VM host stored under the base
               directory path argument. The search pattern may contain
               wildcards. Subdirectories will be searched if the 3rd argument is
               not supplied.

=cut

sub find_files {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the arguments
	my ($base_directory_path, $search_pattern, $search_subdirectories) = @_;
	if (!$base_directory_path || !$search_pattern) {
		notify($ERRORS{'WARNING'}, 0, "base directory path and search pattern arguments were not specified");
		return;
	}
	
	$search_subdirectories = 1 if !defined($search_subdirectories);
	
	$base_directory_path = $self->_get_normal_path($base_directory_path) || return;
	
	# Get the file info
	my $file_info = $self->_get_file_info("$base_directory_path/$search_pattern", $search_subdirectories);
	if (!defined($file_info)) {
		notify($ERRORS{'WARNING'}, 0, "unable to find files, failed to get file info for: $base_directory_path/$search_pattern");
		return;
	}
	
	# Loop through the keys of the file info hash
	my @file_paths;
	for my $file_path (keys(%{$file_info})) {
		# Add the file path to the return array
		push @file_paths, $self->_get_normal_path($file_path);
		
		# vmdk files will have a diskExtents key
		# The extents must be added to the return array
		if (defined($file_info->{$file_path}->{diskExtents})) {
			for my $disk_extent (@{$file_info->{$file_path}->{diskExtents}}) {
				# Convert the datastore file paths to normal file paths
				$disk_extent = $self->_get_normal_path($disk_extent);
				push @file_paths, $self->_get_normal_path($disk_extent);
			}
		}
	}
	
	@file_paths = sort @file_paths;
	notify($ERRORS{'DEBUG'}, 0, "matching file count: " . scalar(@file_paths));
	return @file_paths;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 get_available_space

 Parameters  : $path
 Returns     : integer
 Description : Returns the bytes available in the path specified by the
               argument.

=cut

sub get_available_space {
	my $self = shift;
	if (ref($self) !~ /module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the path argument
	my $path = shift;
	if (!$path) {
		notify($ERRORS{'WARNING'}, 0, "path argument was not specified");
		return;
	}
	
	# Get the datastore name
	my $datastore_name = $self->_get_datastore_name($path) || return;
	
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	
	# Get the datastore info hash
	my $datastore_info = $self->_get_datastore_info() || return;
	
	my $available_bytes = $datastore_info->{$datastore_name}{freeSpace};
	if (!defined($available_bytes)) {
		notify($ERRORS{'WARNING'}, 0, "datastore $datastore_name freeSpace key does not exist in datastore info:\n" . format_data($datastore_info));
		return;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "space available in $datastore_name datastore on $vmhost_hostname: " . format_number($available_bytes) . " bytes");
	return $available_bytes;
}

##############################################################################

=head1 PRIVATE OBJECT METHODS

=cut

#/////////////////////////////////////////////////////////////////////////////

=head2 initialize

 Parameters  : none
 Returns     : boolean
 Description : Initializes the vSphere SDK object by establishing a connection
               to the VM host.

=cut

sub initialize {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Override the die handler because process will die if VMware Perl libraries aren't installed
	local $SIG{__DIE__} = sub{};
	
	eval "use VMware::VIRuntime; use VMware::VILib; use VMware::VIExt";
	if ($EVAL_ERROR) {
		notify($ERRORS{'OK'}, 0, "vSphere SDK for Perl does not appear to be installed on this managment node, unable to load VMware vSphere SDK Perl modules");
		return 0;
	}
	notify($ERRORS{'DEBUG'}, 0, "loaded VMware vSphere SDK modules");
	
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	my $vmhost_username = $self->data->get_vmhost_profile_username();
	my $vmhost_password = $self->data->get_vmhost_profile_password();
	
	if (!$vmhost_hostname) {
		notify($ERRORS{'WARNING'}, 0, "VM host name could not be retrieved");
		return;
	}
	elsif (!$vmhost_username) {
		notify($ERRORS{'DEBUG'}, 0, "unable to use vSphere SDK, VM host username is not configured in the database for the VM profile");
		return;
	}
	elsif (!$vmhost_password) {
		notify($ERRORS{'DEBUG'}, 0, "unable to use vSphere SDK, VM host password is not configured in the database for the VM profile");
		return;
	}
	
	Opts::set_option('username', $vmhost_username);
	Opts::set_option('password', $vmhost_password);
	
	# Override the die handler
	local $SIG{__DIE__} = sub{};
	
	# Assemble the URLs to try, URL will vary based on the VMware product
	my @possible_vmhost_urls = (
		"https://$vmhost_hostname/sdk",
		"https://$vmhost_hostname:8333/sdk",
	);
	
	# Also add URLs containing the short host name if the VM hostname is a full DNS name
	if ($vmhost_hostname =~ /\./) {
		my ($vmhost_short_name) = $vmhost_hostname =~ /^([^\.]+)/;
		push @possible_vmhost_urls, "https://$vmhost_short_name/sdk";
		push @possible_vmhost_urls, "https://$vmhost_short_name:8333/sdk";
	}
	
	# Call HostConnect, check how long it takes to connect
	for my $host_url (@possible_vmhost_urls) {
		Opts::set_option('url', $host_url);
		
		notify($ERRORS{'DEBUG'}, 0, "attempting to connect to VM host: $host_url");
		my $result;
		eval { $result = Util::connect(); };
		$result = 'undefined' if !defined($result);
		my $error_message = $@;
		undef $@;
		
		# It's normal if some connection attempts fail - SSH will be used if the vSphere SDK isn't available
		# Don't display a warning unless the error indicates a configuration problem (wrong username or password)
		# Possible error messages:
		#    Cannot complete login due to an incorrect user name or password.
		#    Error connecting to server at 'https://<VM host>/sdk': Connection refused
		if ($error_message && $error_message =~ /incorrect/) {
			notify($ERRORS{'WARNING'}, 0, "unable to connect to VM host because username or password is incorrectly configured in the VM profile ($vmhost_username/$vmhost_password), error: $error_message");
			return;
		}
		elsif (!$result || $error_message) {
			notify($ERRORS{'DEBUG'}, 0, "unable to connect to VM host using URL: $host_url, error:\n$error_message");
		}
		else {
			notify($ERRORS{'OK'}, 0, "connected to VM host: $host_url, username: '$vmhost_username'");
			return 1;
		}
	}
	
	notify($ERRORS{'OK'}, 0, "unable connect to VM host: $vmhost_hostname");
	return;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 _get_file_info

 Parameters  : $file_path
 Returns     : hash reference
 Description : Retrieves information about the file stored in a datastore
               specified by the file path argument on the VM host. The file path
               argument may be a wildcard. A hash reference is returned. The
               hash keys are paths to the files found. Example of returned data:
               {[nfs-datastore] vmwarewin2008-enterprisex86_641635-v0/vmwarewin2008-enterprisex86_641635-v0.vmdk}
                  -{capacityKb} = '15728640'
                  -{controllerType} = 'VirtualLsiLogicController'
                  -{diskType} = 'VirtualDiskSparseVer2BackingInfo'
                  -{fileSize} = '7128891392'
                  -{hardwareVersion} = '4'
                  -{modification} = '2010-05-27T12:14:51Z'
                  -{owner} = 'root'
                  -{path} = 'vmwarewin2008-enterprisex86_641635-v0.vmdk'
                  -{thin} = '1'
                  -{type} = 'VmDiskFileInfo'

=cut

sub _get_file_info {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the arguments
	my ($path_argument, $search_subfolders) = @_;
	if (!$path_argument) {
		notify($ERRORS{'WARNING'}, 0, "file path argument was not specified");
		return;
	}
	
	# Take the path argument apart
	my $base_directory_path = $self->_get_parent_directory_datastore_path($path_argument) || return;
	my $search_pattern = $self->_get_file_name($path_argument) || return;
	
	# Set the default value for $search_subfolders if the argument wasn't passed
	$search_subfolders = 0 if !$search_subfolders;
	
	# Make sure the base directory path is formatted as a datastore path
	my $base_datastore_path = $self->_get_datastore_path($base_directory_path) || return;
	
	# Extract the datastore name from the base directory path
	my $datastore_name = $self->_get_datastore_name($base_directory_path) || return;
	
	# Get a datastore object and host datastore browser object
	my $datastore = $self->_get_datastore_object($datastore_name) || return;
	my $host_datastore_browser = Vim::get_view(mo_ref => $datastore->browser);
	
	# Create HostDatastoreBrowserSearchSpec spec
   my $file_query_flags = FileQueryFlags->new(
		fileOwner => 1,
		fileSize => 1,
		fileType => 1,
		modification => 1,
	);
	
	my $vm_disk_file_query_flags = VmDiskFileQueryFlags->new(
		capacityKb => 1,
		controllerType => 1,
		diskExtents => 1,
		diskType => 1,
		hardwareVersion => 1,
		thin => 1,

	);
	
	my $vm_disk_file_query = VmDiskFileQuery->new(
		details => $vm_disk_file_query_flags,
	);
	
	my @file_queries = (
		$vm_disk_file_query,
		FileQuery->new(),
		FloppyImageFileQuery->new(),
		FolderFileQuery->new(),
		IsoImageFileQuery->new(),
		VmConfigFileQuery->new(),
		VmLogFileQuery->new(),
		VmNvramFileQuery->new(),
		VmSnapshotFileQuery->new(),
	);
	
	my $hostdb_search_spec = HostDatastoreBrowserSearchSpec->new(
		details => $file_query_flags,
		matchPattern => [$search_pattern],
		searchCaseInsensitive => 0,
		sortFoldersFirst => 1,
		query => [@file_queries],
	);
	
	# Override the die handler because fileManager may call it
	local $SIG{__DIE__} = sub{};
	
	# Searches the folder specified by the datastore path and all subfolders based on the searchSpec
	my $task;
	notify($ERRORS{'DEBUG'}, 0, "searching for matching file paths: base directory path: '$base_directory_path', search pattern: '$search_pattern'");
	if ($search_subfolders) {
		eval { $task = $host_datastore_browser->SearchDatastoreSubFolders(datastorePath=>$base_datastore_path, searchSpec=>$hostdb_search_spec); };
	}
	else {
		eval { $task = $host_datastore_browser->SearchDatastore(datastorePath=>$base_datastore_path, searchSpec=>$hostdb_search_spec); };
	}
	
	# Check if an error occurred
	if ($@) {
		if ($@->isa('SoapFault') && ref($@->detail) eq 'FileNotFound') {
			notify($ERRORS{'DEBUG'}, 0, "base directory does not exist: '$base_directory_path'");
			return {};
		}
		else {
			notify($ERRORS{'WARNING'}, 0, "failed to search datastore to determine if file exists\nbase directory path: '$base_directory_path'\nsearch pattern: '$search_pattern'\nerror:\n$@");
			return;
		}
	}
	
	# The $task result with either be an array of scalar depending on the value of $search_subfolders
	# If $search_subfolders = 0, SearchDatastore is called and the result is a scalar
	# If $search_subfolders = 1, SearchDatastoreSubFolders is called and the result is an array
	# Convert the scalar result to an array
	my @folders;
	if (ref($task) eq 'ARRAY') {
		@folders = @{$task};
	}
	else {
		$folders[0] = $task;
	}
	
	my %file_info;
	for my $folder (sort @folders) {
		if ($folder->file) {
			# Retrieve the folder path, format: '[nfs-datastore] vmwarewinxp-base234-v12'
			my $directory_datastore_path =  $folder->folderPath;
			my $directory_normal_path = $self->_get_normal_path($directory_datastore_path);
			
			# Loop through all of the files under the folder
			foreach my $file (@{$folder->file}) {
				my $file_path = $self->_get_datastore_path("$directory_normal_path/" . $file->path);
				
				# Check the file type
				if (ref($file) eq 'FolderFileInfo') {
					# Don't include folders in the results
					next;
				}
				
				$file_info{$file_path} = $file;
				$file_info{$file_path}{type} = ref($file);
			}
		}
	}
	
	#notify($ERRORS{'DEBUG'}, 0, "retrieved info for " . scalar(keys(%file_info)) . " matching files:\n" . format_data(\%file_info));
	return \%file_info;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 _get_datastore_object

 Parameters  : $datastore_name
 Returns     : vSphere SDK datastore object
 Description : Retrieves a datastore object for the datastore specified by the
               datastore name argument.

=cut

sub _get_datastore_object {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	# Get the datastore name argument
	my $datastore_name = shift;
	if (!$datastore_name) {
		notify($ERRORS{'WARNING'}, 0, "datastore name argument was not specified");
		return;
	}
	
	# Get the host view
	my $host_view = VIExt::get_host_view(1);
	
	# Get an array containing datastore managed object references
	my @datastore_mo_refs = @{$host_view->datastore};
	
	# Loop through the datastore managed object references
	# Get a datastore view, add the view's summary to the return hash
	my @datastore_names_found;
	for my $datastore_mo_ref (@datastore_mo_refs) {
		my $datastore = Vim::get_view(mo_ref => $datastore_mo_ref);
		return $datastore if ($datastore_name eq $datastore->summary->name);
		push @datastore_names_found, $datastore->summary->name;
	}
	
	notify($ERRORS{'WARNING'}, 0, "failed to find datastore named $datastore_name, datastore names found:\n" . join("\n", @datastore_names_found));
	return;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 _get_datastore_info

 Parameters  : none
 Returns     : hash reference
 Description : Finds all datastores on the ESX host and returns a hash reference
               containing the datastore information. The keys of the hash are
               the datastore names. Example:
               
               my $datastore_info = $self->_get_datastore_info();
               $datastore_info->{datastore1}{accessible} = '1'
               $datastore_info->{datastore1}{capacity} = '31138512896'
               $datastore_info->{datastore1}{datastore}{type} = 'Datastore'
               $datastore_info->{datastore1}{datastore}{value} = '4bcf0efe-c426acc4-c7e1-001a644d1cc0'
               $datastore_info->{datastore1}{freeSpace} = '30683430912'
               $datastore_info->{datastore1}{name} = 'datastore1'
               $datastore_info->{datastore1}{type} = 'VMFS'
               $datastore_info->{datastore1}{uncommitted} = '0'
               $datastore_info->{datastore1}{url} = '/vmfs/volumes/4bcf0efe-c426acc4-c7e1-001a644d1cc0'

=cut

sub _get_datastore_info {
	my $self = shift;
	if (ref($self) !~ /VCL::Module/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	my $vmhost_hostname = $self->data->get_vmhost_hostname();
	
	# Get the host view
	my $host_view = VIExt::get_host_view(1);
	
	# Get an array containing datastore managed object references
	my @datastore_mo_refs = @{$host_view->datastore};
	
	# Loop through the datastore managed object references
	# Get a datastore view, add the view's summary to the return hash
	my $datastore_info;
	for my $datastore_mo_ref (@datastore_mo_refs) {
		my $datastore_view = Vim::get_view(mo_ref => $datastore_mo_ref);
		my $datastore_name = $datastore_view->summary->name;
		
		# Make sure the datastore is accessible
		# Don't return info for inaccessible datastores
		my $datastore_accessible = $datastore_view->summary->accessible;
		if (!$datastore_accessible) {
			notify($ERRORS{'WARNING'}, 0, "datastore '$datastore_name' is mounted on $vmhost_hostname but not accessible");
			next;
		}
		
		my $datastore_url = $datastore_view->summary->url;
		if (!$datastore_url) {
			notify($ERRORS{'WARNING'}, 0, "unable to retrieve URL for datastore '$datastore_name'");
			next;
		}
		
		if ($datastore_url =~ /^\/vmfs\/volumes/i) {
			$datastore_view->summary->{normal_path} = "/vmfs/volumes/$datastore_name";
		}
		else {
			$datastore_view->summary->{normal_path} = $datastore_url;
		}
		
		$datastore_info->{$datastore_name} = $datastore_view->summary;
	}
	
	return $datastore_info;
}

#/////////////////////////////////////////////////////////////////////////////

1;
__END__

=head1 SEE ALSO

L<http://cwiki.apache.org/VCL/>

=cut
