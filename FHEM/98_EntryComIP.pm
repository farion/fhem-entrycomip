# $Id$
##############################################################################
#
#     98_EntryComIP.pm
#     A FHEM Perl module to handle 2N EntryCom IP devices.
#
#     Copyright by Frieder Reinhold
#     e-mail: reinhold@trigon-media.com
#
#     Based and inspired by
#       GEOFANCY by Julian Pawlowski
#       FRITZBOX by Torsten Poitzsch
#       OPENWEATHER by Torsten Poitzsch
#
#     Module is based on the HTTP-API of the 2n Helios device.
#     You need at least an integration license.
#
#     Device documentations can be found here:
#     https://wiki.2n.cz/download/attachments/23102595/2N_Helios_IP_Automation_Manual_EN_2.14.pdf
#     https://wiki.2n.cz/download/attachments/23102595/2N_Helios_IP_HTTP_API_Manual_EN_2.14.pdf
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#
# Version: 0.0.2
#
# Major Version History:
# - 0.0.2 - 2016-11-29
# -- Added ignoreSslErrors to ignore broken default certificate.
#
# - 0.0.1 - 2016-01-28
# -- First release
# -- Features:
# --- get info
# --- get status
# --- control io (outputs, leds etc.)
# --- handling of log subscriptions and events
# --- audio test
#
# TODO
# - Support for more events
# - switches
# - phone
# - call
# - firmware update
# - config upload
# - camera
# - display
#
##############################################################################

package main;

use strict;
use warnings;
use vars qw(%data);
use HttpUtils;
use Time::Local;
use Data::Dumper;
use Switch;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

sub EntryComIP_Set($@);
sub EntryComIP_Define($$);
sub EntryComIP_Undefine($$);

###################################
sub EntryComIP_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "[EntryComIP] Entering";

    $hash->{SetFn} = "EntryComIP_Set";
    $hash->{DefFn} = "EntryComIP_Define";
    $hash->{UndefFn} = "EntryComIP_Undefine";
    $hash->{AttrFn} = "EntryComIP_Attr";
    $hash->{AttrList} = "user "
        ."ip "
        ."pollTimeout "
        ."pollsPerThread "
	."ignoreSslErrors:0,1 "
        .$readingFnAttributes;
}

####################################
sub EntryComIP_Attr($@)
{
    my ($cmd, $name, $aName, $aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    my $hash = $defs{$name};

    if ($aName eq "ip") {
        if ($cmd eq "set") {
            $hash->{HOST} = $aVal;
        }
    }

    return undef;
}

###################################
sub EntryComIP_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t]+", $def, 5 );

    return "Usage: define <name> EntryComIP <host>"

        if ( int(@a) != 3 );

    $hash->{NAME} = $a[0];
    $hash->{HOST} = "undefined";
    $hash->{HOST} = $a[2] if defined $a[2];

    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "state", "initialized" );
    readingsBulkUpdate($hash, "logSubscriptionId","");
    readingsEndUpdate( $hash, 1 );

    $hash->{helper}{PULL_RESTART_DELAY}=1;

    InternalTimer(gettimeofday()+2, "EntryComIP_Start", $hash, 0);

    return undef;
}

###################################
sub EntryComIP_Start($){
    my ($hash) = @_;
    EntryComIP_GetAll($hash);
    EntryComIP_Polling_Start($hash);
}

###################################
sub EntryComIP_Undefine($$) {

    my ( $hash, $name ) = @_;

    BlockingKill($hash->{helper}{RUNNING_PID_INFO}) if (defined($hash->{helper}{RUNNING_PID_INFO}));
    BlockingKill($hash->{helper}{RUNNING_PID_STATUS}) if (defined($hash->{helper}{RUNNING_PID_STATUS}));
    BlockingKill($hash->{helper}{RUNNING_PID_RESTART}) if (defined($hash->{helper}{RUNNING_PID_RESTART}));
    BlockingKill($hash->{helper}{RUNNING_PID_TRIGGER}) if (defined($hash->{helper}{RUNNING_PID_TRIGGER}));
    BlockingKill($hash->{helper}{RUNNING_PID_IOCAPS}) if (defined($hash->{helper}{RUNNING_PID_IOCAPS}));
    BlockingKill($hash->{helper}{RUNNING_PID_IOSTATUS}) if (defined($hash->{helper}{RUNNING_PID_IOSTATUS}));
    BlockingKill($hash->{helper}{RUNNING_PID_IOCTRL}) if (defined($hash->{helper}{RUNNING_PID_IOCTRL}));
    BlockingKill($hash->{helper}{RUNNING_PID_AUDIOTEST}) if (defined($hash->{helper}{RUNNING_PID_AUDIOTEST}));
    BlockingKill($hash->{helper}{RUNNING_PID_LOG}) if (defined($hash->{helper}{RUNNING_PID_LOG}));

    return undef;
}

###################################
sub EntryComIP_Set($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $state = $hash->{STATE};

    Log3 $name, 5, "[EntryComIP] Called set";

    return "No Argument given" if ( !defined( $a[1] ) );

    my $usage = "Unknown argument ".$a[1].", choose one of clear:readings getAll getInfo getStatus restart trigger getIoCaps getIoStatus password ioCtrl audioTest startPolling stopPolling";

    # clear
    if ($a[1] eq "clear") {
        if ($a[2]) {

            # readings
            if ($a[2] eq "readings") {
                EntryComIP_ClearReadings($hash);
            }
            else {
                return $usage;
            }

        }
        else {
            return "No Argument given, choose one of readings ";
        }
    }
    elsif ($a[1] eq "password") {
        return EntryComIP_storePassword ( $hash, $a[2] );
    }
    elsif ($a[1] eq "getAll") {
        return EntryComIP_GetAll($hash);
    }
    elsif ($a[1] eq "getInfo") {
        return EntryComIP_GetInfo($hash);
    }
    elsif ($a[1] eq "getStatus") {
        return EntryComIP_GetStatus($hash);
    }
    elsif ($a[1] eq "restart") {
        return EntryComIP_Restart($hash);
    }
    elsif ($a[1] eq "getIoCaps") {
        return EntryComIP_GetIoCaps($hash);
    }
    elsif ($a[1] eq "getIoStatus") {
        return EntryComIP_GetIoStatus($hash);
    }
    elsif ($a[1] eq "ioCtrl") {
        return EntryComIP_IoCtrl($hash, $a[2], $a[3]);
    }
    elsif ($a[1] eq "audioTest") {
        return EntryComIP_AudioTest($hash);
    }
    elsif ($a[1] eq "startPolling") {
        return EntryComIP_Polling_Start($hash);
    }
    elsif ($a[1] eq "stopPolling") {
        return EntryComIP_Polling_Stop($hash);
    }

    # return usage hint
    else {
        return $usage;
    }

    return undef;
}

##########################################
sub EntryComIP_ClearReadings($){
    my ( $hash ) = @_;

    delete $hash->{READINGS};
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "state", "clearedReadings" );
    readingsEndUpdate( $hash, 1 );
}

##########################################
sub EntryComIP_GetAll($) {

    my ( $hash ) = @_;

    EntryComIP_GetInfo($hash);
    EntryComIP_GetStatus($hash);
    EntryComIP_GetIoCaps($hash);
    EntryComIP_GetIoStatus($hash);

    return undef;
}

############################################################################################################
#
#   Implementation of the SOAP API to get real time events
#
############################################################################################################


############################################################################################################
#
#   Password helper functions taken from FRITZBOX module by Torsten Poitzsch
#
############################################################################################################

sub EntryComIP_storePassword($$)
{
    my ($hash, $password) = @_;

    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;

    my $enc_pwd = "";

    if(eval "use Digest::MD5;1")
    {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }

    for my $char (split //, $password)
    {
        my $encode=chop($key);
        $enc_pwd.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }

    my $err = setKeyValue($index, $enc_pwd);
    return "error while saving the password - $err" if(defined($err));

    return "password successfully saved";
}

##########################################
sub EntryComIP_readPassword($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;

    my ($password, $err);

    Log3 $name, 5, "[EntryComIP] Read EntryComIP password from file";
    ($err, $password) = getKeyValue($index);

    if ( defined($err) ) {
        Log3 $name, 4, "[EntryComIP] Unable to read EntryComIP password from file: $err";
        return undef;
    }

    if ( defined($password) ) {
        if ( eval "use Digest::MD5;1" ) {
            $key = Digest::MD5::md5_hex(unpack "H*", $key);
            $key .= Digest::MD5::md5_hex($key);
        }

        my $dec_pwd = '';

        for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g)) {
            my $decode=chop($key);
            $dec_pwd.=chr(ord($char)^ord($decode));
            $key=$decode.$key;
        }

        return $dec_pwd;
    }
    else {
        Log3 $name, 4, "[EntryComIP] No password in file";
        return undef;
    }
}


############################################################################################################
#
#   API HTTP HELPER API
#
############################################################################################################

sub EntryComIP_doGetRequest($$$$) {

    my ($hash, $name, $url, $useauth) = @_;

    return EntryComIP_doRequest($hash, $name, $url, $useauth, "GET","",10);
}

sub EntryComIP_doGetRequestWithTimeout($$$$$){
    my ($hash, $name, $url, $useauth, $timeout) = @_;

    return EntryComIP_doRequest($hash, $name, $url, $useauth, "GET", "", $timeout);
}

sub EntryComIP_doPostRequest($$$$$) {

    my ($hash, $name, $url, $useauth, $data) = @_;

    return EntryComIP_doRequest($hash, $name, $url, $useauth, "POST",$data,10);
}

sub EntryComIP_doRequest($$$$$$$)
{
    my ($hash, $name, $url, $useauth, $method, $data, $timeout) = @_;
    my $err_log = "";

    if ( $useauth ) {
        Log3 $name, 5, "[EntryComIP] API request with authentication to ".$url;
    }else {
        Log3 $name, 5, "[EntryComIP] API request to ".$url;
    }

    my $agent = LWP::UserAgent->new(
        env_proxy         => 1,
        keep_alive        => 1,
        protocols_allowed => [ 'https' ],
        timeout           => $timeout,
        agent             => "Mozilla/5.0 (FHEM)" );

    my $ignoresslerrors = AttrVal( $name, "ignoreSslErrors", 0 );

    if ( $ignoresslerrors == 1) {
      $agent->ssl_opts(verify_hostname => 0,
                     SSL_verify_mode => 0x00);
    }


    my $request;
    if ( $method eq "POST" ) {
         my $header = new HTTP::Headers (
            'Content-Type'   => 'text/xml; charset=utf-8'
        );
        $request = new HTTP::Request('POST',$url,$header,$data);
    }else {
        $request = HTTP::Request->new( "GET" => $url );
    }

    if( $useauth ) {
        $request->authorization_basic(
            AttrVal( $name, "user", "" ),
            EntryComIP_readPassword($hash)
        );
    }

    my $response = $agent->request($request);
    $err_log = "Error: Can't get $url -- ".$response->status_line
        unless $response->is_success;

    if ($err_log ne "")
    {
        return $name."|0|".$err_log." Body: ".$response->content;
    }

    Log3 $name, 5, "[EntryComIP] API said: ".$response->content;

    my $message = encode_base64($response->content, "");

    return $name."|1|".$message;

}

##########################################
sub EntryComIP_Check_API_Success($)
{

    my ($string) = @_;
    my ($name, $success, $result) = split("\\|", $string);
    my $hash = $defs{$name};

    if ($success == 1) {
        my $message = decode_base64($result);
        my $decoded_json = decode_json( $message );

        if ($decoded_json->{'success'} ne "true") {
                readingsBeginUpdate($hash);
            if (defined $decoded_json->{'error'}{'code'} && defined $decoded_json->{'error'}{'description'}) {

                readingsBulkUpdate(
                    $hash,
                    "lastErrorResult",
                    "API error #".$decoded_json->{'error'}{'code'}.": ".$decoded_json->{'error'}{'description'}
                );

            } else {
                readingsBulkUpdate($hash, "lastErrorResult", "API error unknown");
            }
            Log3 $name, 4, "[EntryComIP] API does not deliver success = true. ".$string;
            readingsBulkUpdate($hash, "state", "Error");
            readingsEndUpdate( $hash, 1 );
            return ($hash, "", $decoded_json);
        }else{
            return ($hash, $result, $decoded_json);
        }

    }else{
        readingsBeginUpdate($hash);
        Log3  $name, 4, "[EntryComIP] API did fail without response. ".$string;
        readingsBulkUpdate($hash, "lastErrorResult",$string);
        readingsBulkUpdate($hash, "state", "Error");
        readingsEndUpdate( $hash, 1 );
        return ($hash, "", "");
    }
}

##########################################
sub EntryComIP_checkJson($$$){

    my ($var,$hash,$result) = @_;

    if (!defined $var) {
        readingsBeginUpdate($hash);
        Log3 $hash->{NAME}, 4, "[EntryComIP] API response did not contain expected JSON.";
        readingsBulkUpdate($hash, "lastErrorResult", $result);
        readingsBulkUpdate($hash, "state", "Json-Error");
        readingsEndUpdate( $hash, 1 );
        return 0;
    }

    return 1;
}


############################################################################################################
#
#   INFO API
#
############################################################################################################

sub EntryComIP_GetInfo($) {

    my ( $hash ) = @_;

    Log3 $hash->{NAME}, 2, "[EntryComIP] Info started.";

    $hash->{helper}{RUNNING_PID_INFO} = BlockingCall("EntryComIP_Info_Run", $hash->{NAME},
        "EntryComIP_Info_Done", 20,
        "EntryComIP_Info_UpdateAborted", $hash)
        unless (exists($hash->{helper}{RUNNING_PID_INFO}));
    return undef;
}

##########################################
sub EntryComIP_Info_Run ($)
{
    my ($name) = @_;
    my $hash = $defs{$name};
    my $url = "https://".$hash->{HOST}."/api/system/info";

    return EntryComIP_doGetRequest($hash, $name, $url, 0);

}

##########################################
sub EntryComIP_Info_Done($)
{
    my ($string) = @_;
    return unless defined $string;

    my ($hash, $result, $decoded_json) = EntryComIP_Check_API_Success($string);
    my $name = $hash->{NAME};

    delete($hash->{helper}{RUNNING_PID_INFO});

    return undef unless $result;

    Log3 $name, 5, "Info done.";

    if (!EntryComIP_checkJson($decoded_json->{'result'}{'variant'},$hash,$result) ||
    !EntryComIP_checkJson($decoded_json->{'result'}{'serialNumber'},$hash,$result) ||
    !EntryComIP_checkJson($decoded_json->{'result'}{'hwVersion'},$hash,$result) ||
    !EntryComIP_checkJson($decoded_json->{'result'}{'swVersion'},$hash,$result) ||
    !EntryComIP_checkJson($decoded_json->{'result'}{'buildType'},$hash,$result) ||
    !EntryComIP_checkJson($decoded_json->{'result'}{'deviceName'},$hash,$result)) { return undef; }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "variant", $decoded_json->{'result'}{'variant'});
    readingsBulkUpdate($hash, "serialNumber", $decoded_json->{'result'}{'serialNumber'});
    readingsBulkUpdate($hash, "hwVersion", $decoded_json->{'result'}{'hwVersion'});
    readingsBulkUpdate($hash, "swVersion", $decoded_json->{'result'}{'swVersion'});
    readingsBulkUpdate($hash, "buildType", $decoded_json->{'result'}{'buildType'});
    readingsBulkUpdate($hash, "deviceName", $decoded_json->{'result'}{'deviceName'});
    readingsBulkUpdate($hash, "lastErrorResult", "");
    readingsBulkUpdate($hash, "state", "Info Done");
    readingsEndUpdate( $hash, 1 );

    return undef;
}

##########################################
sub EntryComIP_Info_UpdateAborted($)
{
    my ($hash) = @_;
    Log3 $hash->{NAME}, 4, "[EntryComIP] Info aborted.";
    delete($hash->{helper}{RUNNING_PID_INFO});

    return undef;
}


############################################################################################################
#
#   STATUS API
#
############################################################################################################

sub EntryComIP_GetStatus($) {

    my ( $hash ) = @_;

    Log3 $hash->{NAME}, 5, "[EntryComIP] Get status started.";

    $hash->{helper}{RUNNING_PID_STATUS} = BlockingCall("EntryComIP_Status_Run", $hash->{NAME},
        "EntryComIP_Status_Done", 20,
        "EntryComIP_Status_UpdateAborted", $hash)
        unless (exists($hash->{helper}{RUNNING_PID_STATUS}));

    return undef;
}

##########################################
sub EntryComIP_Status_Run ($)
{
    my ($name) = @_;
    my $hash = $defs{$name};
    my $url = "https://".$hash->{HOST}."/api/system/status";

    return EntryComIP_doGetRequest($hash, $name, $url, 1);
}

##########################################
sub EntryComIP_Status_Done($)
{
    my ($string) = @_;
    return unless defined $string;

    my ($hash, $result, $decoded_json) = EntryComIP_Check_API_Success($string);
    my $name = $hash->{NAME};

    delete($hash->{helper}{RUNNING_PID_STATUS});

    return undef unless $result;

    Log3 $name, 5, "Get status done.";

    if (!EntryComIP_checkJson($decoded_json->{'result'}{'systemTime'},$hash,$result) ||
        !EntryComIP_checkJson($decoded_json->{'result'}{'upTime'},$hash,$result))  { return undef; }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "systemTime", $decoded_json->{'result'}{'systemTime'});
    readingsBulkUpdate($hash, "upTime", $decoded_json->{'result'}{'upTime'});
    readingsBulkUpdate($hash, "lastErrorResult", "");
    readingsBulkUpdate($hash, "state", "Status Done");
    readingsEndUpdate( $hash, 1 );

    return undef;
}

##########################################
sub EntryComIP_Status_UpdateAborted($)
{
    my ($hash) = @_;
    Log3 $hash->{NAME}, 4, "[EntryComIP] Get status aborted.";
    delete($hash->{helper}{RUNNING_PID_STATUS});

    return undef;
}


############################################################################################################
#
#   RESTART API
#
############################################################################################################

sub EntryComIP_Restart($) {

    my ( $hash ) = @_;

    Log3 $hash->{NAME}, 5, "[EntryComIP] Restart started.";

    $hash->{helper}{RUNNING_PID_RESTART} = BlockingCall("EntryComIP_Restart_Run", $hash->{NAME},
        "EntryComIP_Restart_Done", 20,
        "EntryComIP_Restart_UpdateAborted", $hash)
        unless (exists($hash->{helper}{RUNNING_PID_RESTART}));

    return undef;
}

##########################################
sub EntryComIP_Restart_Run ($)
{
    my ($name) = @_;
    my $hash = $defs{$name};
    my $url = "https://".$hash->{HOST}."/api/system/restart";

    return EntryComIP_doGetRequest($hash, $name, $url, 1);
}

##########################################
sub EntryComIP_Restart_Done($)
{
    my ($string) = @_;
    return unless defined $string;

    my ($hash, $result, $decoded_json) = EntryComIP_Check_API_Success($string);
    my $name = $hash->{NAME};

    delete($hash->{helper}{RUNNING_PID_RESTART});

    return undef unless $result;

    Log3 $name, 5, "[EntryComIP] Restart done.";

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastErrorResult", "");
    readingsBulkUpdate($hash, "state", "Restart Done");
    readingsEndUpdate( $hash, 1 );

    return undef;
}

##########################################
sub EntryComIP_Restart_UpdateAborted($)
{
    my ($hash) = @_;
    Log3 $hash->{NAME}, 4, "[EntryComIP] Restart aborted.";
    delete($hash->{helper}{RUNNING_PID_RESTART});

    return undef;
}

############################################################################################################
#
#   TRIGGER API
#
############################################################################################################

sub EntryComIP_Trigger($) {

    my ( $hash, $ipWithParams ) = @_;

    Log3 $hash->{NAME}, 5, "[EntryComIP] Trigger started:".$ipWithParams;

    my $encIdWithParams = encode_base64($ipWithParams, "");
    $hash->{helper}{RUNNING_PID_TRIGGER} = BlockingCall("EntryComIP_Trigger_Run", $hash->{NAME}."|".$encIdWithParams,
        "EntryComIP_Trigger_Done", 20,
        "EntryComIP_Trigger_UpdateAborted", $hash)
        unless (exists($hash->{helper}{RUNNING_PID_TRIGGER}));

    return undef;
}


##########################################
sub EntryComIP_Trigger_Run ($)
{
    my ($string) = @_;
    my ($name, $encIdWithParams) = split("\\|", $string);
    my $hash = $defs{$name};
    my $idWithParams = decode_base64($encIdWithParams);
    my $url = "https://".$hash->{HOST}."/enu/trigger/".$idWithParams;

    return EntryComIP_doGetRequest($hash, $name, $url, 1);

}

##########################################
sub EntryComIP_Trigger_Done($)
{
    my ($string) = @_;
    return unless defined $string;

    my ($hash, $result, $decoded_json) = EntryComIP_Check_API_Success($string);
    my $name = $hash->{NAME};

    delete($hash->{helper}{RUNNING_PID_TRIGGER});

    return undef unless $result;

    Log3 $name, 5, "[EntryComIP] Trigger done";

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastErrorResult", "");
    readingsBulkUpdate($hash, "state", "Trigger Done");
    readingsEndUpdate( $hash, 1 );

    return undef;
}

##########################################
sub EntryComIP_Trigger_UpdateAborted($)
{
    my ($hash) = @_;
    Log3 $hash->{NAME}, 5, "[EntryComIP] Trigger aborted";
    delete($hash->{helper}{RUNNING_PID_TRIGGER});

    return undef;
}



############################################################################################################
#
#   IO CAPS API
#
############################################################################################################

sub EntryComIP_GetIoCaps($) {

    my ( $hash ) = @_;

    Log3 $hash->{NAME}, 5, "[EntryComIP] Get IO info started.";

    $hash->{helper}{RUNNING_PID_IOCAPS} = BlockingCall("EntryComIP_IoCaps_Run", $hash->{NAME},
        "EntryComIP_IoCaps_Done", 20,
        "EntryComIP_IoCaps_UpdateAborted", $hash)
        unless (exists($hash->{helper}{RUNNING_PID_IOCAPS}));

    return undef;
}


##########################################
sub EntryComIP_IoCaps_Run ($)
{
    my ($name) = @_;
    my $hash = $defs{$name};
    my $url = "https://".$hash->{HOST}."/api/io/caps";

    return EntryComIP_doGetRequest($hash, $name, $url, 1);
}

##########################################
sub EntryComIP_IoCaps_Done($)
{
    my ($string) = @_;
    return unless defined $string;

    my ($hash,  $result, $decoded_json) = EntryComIP_Check_API_Success($string);
    my $name = $hash->{NAME};

    delete($hash->{helper}{RUNNING_PID_IOCAPS});

    return undef unless $result;

    Log3 $name, 5, "[EntryComIP] Get IO info done.";

    if ( !EntryComIP_checkJson($decoded_json->{'result'}{'ports'},$hash,$result) )  { return undef; }

    readingsBeginUpdate($hash);

    my $port;
    my $ports = $decoded_json->{'result'}{'ports'};
    foreach $port ( @$ports) {
        if( !$hash->{READINGS}{$port->{'port'}}{VAL} ){
            readingsBulkUpdate($hash, $port->{'port'}, "");
        }
    }

    readingsBulkUpdate($hash, "lastErrorResult", "");
    readingsBulkUpdate($hash, "state", "IO Caps Done");
    readingsEndUpdate( $hash, 1 );

    return undef;
}

##########################################
sub EntryComIP_IoCaps_UpdateAborted($)
{
    my ($hash) = @_;
    Log3 $hash->{NAME}, 4, "[EntryComIP] Get IO info aborted.";
    delete($hash->{helper}{RUNNING_PID_IOCAPS});

    return undef;
}

############################################################################################################
#
#   IO STATUS API
#
############################################################################################################

sub EntryComIP_GetIoStatus($) {

    my ( $hash ) = @_;

    Log3 $hash->{NAME}, 5, "[EntryComIP] Get IO status started.";

    $hash->{helper}{RUNNING_PID_IOSTATUS} = BlockingCall("EntryComIP_IoStatus_Run", $hash->{NAME},
        "EntryComIP_IoStatus_Done", 20,
        "EntryComIP_IoStatus_UpdateAborted", $hash)
        unless (exists($hash->{helper}{RUNNING_PID_IOSTATUS}));

    return undef;
}

##########################################
sub EntryComIP_IoStatus_Run ($)
{
    my ($name) = @_;
    my $hash = $defs{$name};
    my $url = "https://".$hash->{HOST}."/api/io/status";

    return EntryComIP_doGetRequest($hash, $name, $url, 1);
}

##########################################
sub EntryComIP_IoStatus_Done($)
{
    my ($string) = @_;
    return unless defined $string;

    my ($hash, $result, $decoded_json) = EntryComIP_Check_API_Success($string);
    my $name = $hash->{NAME};

    delete($hash->{helper}{RUNNING_PID_IOSTATUS});

    return undef unless $result;

    Log3 $name, 5, "[EntryComIP] Get IO status done.";

    if ( !EntryComIP_checkJson($decoded_json->{'result'}{'ports'},$hash,$result) )  { return undef; }

    readingsBeginUpdate($hash);

    my $port;
    my $ports = $decoded_json->{'result'}{'ports'};
    foreach $port ( @$ports) {
        readingsBulkUpdate($hash, $port->{'port'}, $port->{'state'}?"on":"off");
    }

    readingsBulkUpdate($hash, "lastErrorResult", "");
    readingsBulkUpdate($hash, "state", "IO Status Done");
    readingsEndUpdate( $hash, 1 );

    return undef;
}

##########################################
sub EntryComIP_IoStatus_UpdateAborted($)
{
    my ($hash) = @_;
    Log3 $hash->{NAME}, 4, "[EntryComIP] Get IO status aborted.";
    delete($hash->{helper}{RUNNING_PID_IOSTATUS});

    return undef;
}


############################################################################################################
#
#   IO CTRL API
#
############################################################################################################

sub EntryComIP_IoCtrl($$$) {

    my ( $hash, $port, $action ) = @_;

    Log3 $hash->{NAME}, 5, "[EntryComIP] Set IO started: ".$port."=".$action;

    $hash->{helper}{RUNNING_PID_IOCTRL} = BlockingCall("EntryComIP_IoCtrl_Run", $hash->{NAME}."|".$port."|".$action,
        "EntryComIP_IoCtrl_Done", 20,
        "EntryComIP_IoCtrl_UpdateAborted", $hash)
        unless (exists($hash->{helper}{RUNNING_PID_IOCTRL}));

    return undef;
}

##########################################
sub EntryComIP_IoCtrl_Run ($)
{
    my ($string) = @_;
    my ($name, $port, $action) = split("\\|", $string);
    my $hash = $defs{$name};
    my $url = "https://".$hash->{HOST}."/api/io/ctrl?port=".$port."&action=".$action;

    return EntryComIP_doGetRequest($hash, $name, $url, 1);

}

##########################################
sub EntryComIP_IoCtrl_Done($)
{
    my ($string) = @_;
    return unless defined $string;

    my ($hash, $result, $decoded_json) = EntryComIP_Check_API_Success($string);
    my $name = $hash->{NAME};

    delete($hash->{helper}{RUNNING_PID_IOCTRL});

    return undef unless $result;

    Log3 $name, 5, "[EntryComIP] Set IO done.";

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastErrorResult", "");
    readingsBulkUpdate($hash, "state", "IO Ctrl Done");
    readingsEndUpdate( $hash, 1 );

    return undef;
}

##########################################
sub EntryComIP_IoCtrl_UpdateAborted($)
{
    my ($hash) = @_;
    Log3 $hash->{NAME}, 4, "[EntryComIP] Set IO aborted.";
    delete($hash->{helper}{RUNNING_PID_IOCTRL});

    return undef;
}

############################################################################################################
#
#   AUDIO TEST API
#
############################################################################################################

sub EntryComIP_AudioTest($) {

    my ( $hash ) = @_;

    Log3 $hash->{NAME}, 5, "[EntryComIP] Audio test started.";

    $hash->{helper}{RUNNING_PID_AUDIOTEST} = BlockingCall("EntryComIP_AudioTest_Run", $hash->{NAME},
        "EntryComIP_AudioTest_Done", 20,
        "EntryComIP_AudioTest_UpdateAborted", $hash)
        unless (exists($hash->{helper}{RUNNING_PID_AUDIOTEST}));

    return undef;
}


##########################################
sub EntryComIP_AudioTest_Run ($)
{
    my ($name) = @_;
    my $hash = $defs{$name};
    my $url = "https://".$hash->{HOST}."/api/audio/test";

    return EntryComIP_doGetRequest($hash, $name, $url, 1);
}

##########################################
sub EntryComIP_AudioTest_Done($)
{
    my ($string) = @_;
    return unless defined $string;

    my ($hash, $result, $decoded_json) = EntryComIP_Check_API_Success($string);
    my $name = $hash->{NAME};

    delete($hash->{helper}{RUNNING_PID_AUDIOTEST});

    return undef unless $result;

    Log3 $name, 5, "[EntryComIP] Audio test done.";

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "lastErrorResult", "");
    readingsBulkUpdate($hash, "state", "Audio Test Done");
    readingsEndUpdate( $hash, 1 );

    return undef;
}

##########################################
sub EntryComIP_AudioTest_UpdateAborted($)
{
    my ($hash) = @_;
    Log3 $hash->{NAME}, 5, "[EntryComIP] Audio test aborted.";
    delete($hash->{helper}{RUNNING_PID_AUDIOTEST});

    return undef;
}

############################################################################################################
#
#   SUBSCRIPTION API
#
############################################################################################################

sub EntryComIP_Polling_Stop($) {
    my ( $hash ) = @_;

    Log3 $hash->{NAME}, 5, "[EntryComIP] Pull stop.";

    BlockingKill($hash->{helper}{RUNNING_PID_LOG}) if (defined($hash->{helper}{RUNNING_PID_LOG}));

    delete ( $hash->{helper}{RUNNING_PID_LOG} );

    return undef;
}

##########################################
sub EntryComIP_Polling_Start($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "[EntryComIP] Pull start.";

    my $timeout = AttrVal( $name, "pollTimeout", 20 );
    my $polls_per_thread = AttrVal( $name, "pollsPerThread", 30 );

    $hash->{helper}{RUNNING_PID_LOG} = BlockingCall("EntryComIP_Polling_Run", $name,
        "EntryComIP_Polling_Done", $timeout*$polls_per_thread*2,
        "EntryComIP_Polling_Aborted", $hash)
        unless (exists($hash->{helper}{RUNNING_PID_LOG}));

    return undef;
}

##########################################
sub EntryComIP_Polling_Run($) {

    my ($name) = @_;
    my $hash = $defs{$name};

    Log3 $name, 5, "[EntryComIP] Pull run.";

    my $polls_per_thread = AttrVal( $name, "pollsPerThread", 30 );

    $hash->{helper}{SUBSCRIPTIONID} = EntryComIP_Polling_GetSubscriptionId($hash);
    if($hash->{helper}{SUBSCRIPTIONID}){

        for(my $i = 0; $i < $polls_per_thread; $i++) {
            my $resultString = EntryComIP_Polling_Poll($hash);
            return $name."|0|no poll result" unless $resultString;
            my ($hash, $result, $decoded_json) = EntryComIP_Check_API_Success($resultString);
            return $name."|0|no json result" unless $result;

            my $events = $decoded_json->{'result'}{'events'};

            if ( scalar(@$events) > 0) {
                Log3 $name, 5, scalar(@$events)." rvent(s) found ... return block.";
                return $resultString;
            }
        }
    }

    Log3 $name, 5, "Poll round finished ... return block.";
    return $name."|1|".encode_base64('{"success":true,"result":{"events":[]}}',"");
}

##########################################
sub EntryComIP_Polling_GetSubscriptionId($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    if(!$hash->{helper}{SUBSCRIPTIONID}){

        Log3 $name, 5, "[EntryComIP] Pull get Subscription Id .". $hash->{HOST};

        my $url = "https://".$hash->{HOST}."/api/log/subscribe?duration=20";
        my $resultString = EntryComIP_doGetRequest($hash, $name, $url, 1);
        return undef unless $resultString;
        Log3 $name,5,"[EntryComIP] RESULT ".$resultString;
        my ($hash, $result, $decoded_json) = EntryComIP_Check_API_Success($resultString);
        return undef unless $result;
        if (!EntryComIP_checkJson($decoded_json->{'result'}{'id'},$hash,$result))  { return undef; }
        $hash->{helper}{SUBSCRIPTIONID} = $decoded_json->{'result'}{'id'};
    }

    return $hash->{helper}{SUBSCRIPTIONID};
}

##########################################
sub EntryComIP_Polling_Poll($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    my $timeout = AttrVal( $name, "pollTimeout", 20 );
    my $url = "https://".$hash->{HOST}."/api/log/pull?id=".$hash->{helper}{SUBSCRIPTIONID}."&timeout=".$timeout;

    Log3 $name, 5, "[EntryComIP] Do Poll.";

    return EntryComIP_doGetRequestWithTimeout($hash, $name, $url, 1,$timeout*2);
}


##########################################
sub EntryComIP_Polling_Done($)
{
    my ($string) = @_;
    return unless defined $string;

    my ($hash, $result, $decoded_json) = EntryComIP_Check_API_Success($string);
    my $name = $hash->{NAME};


    Log3 $name, 5, "[EntryComIP] Pull events done.";

    if ( $result ) {

        my $timeout = AttrVal( $name, "pollTimeout", 20 );

        Log3 $name, 5, "[EntryComIP] Pull successful. Updating Readings.";

        readingsBeginUpdate($hash);

        my $event;
        my $events = $decoded_json->{'result'}{'events'};
        foreach $event ( @$events) {

            if ($event->{'event'} eq "OutputChanged") {
                readingsBulkUpdate($hash, $event->{'params'}{'port'}, $event->{'params'}{'state'}?"on":"off");
            } elsif ($event->{'event'} eq "InputChanged") {
                #TODO Test
                readingsBulkUpdate($hash, $event->{'params'}{'port'}, $event->{'params'}{'state'}?"on":"off");
            } elsif ($event->{'event'} eq "KeyPressed") {
                readingsBulkUpdate($hash, "Key".$event->{'params'}{'key'},"Pressed");
            } elsif ($event->{'event'} eq "KeyReleased") {
                readingsBulkUpdate($hash, "Key".$event->{'params'}{'key'},"Released");
            }
        }

        readingsBulkUpdate($hash,"pullUpdate","Success");
        readingsEndUpdate( $hash, 1 );
    }

    delete($hash->{helper}{RUNNING_PID_LOG});
    InternalTimer(gettimeofday()+1, "EntryComIP_Polling_Start", $hash, 0);

    return undef;
}

##########################################
sub EntryComIP_Polling_Aborted($)
{
    my ($hash) = @_;
    Log3 $hash->{NAME}, 5, "[EntryComIP] Pull abort.";
    delete($hash->{helper}{RUNNING_PID_LOG});
    InternalTimer(gettimeofday()+1, "EntryComIP_Polling_Start", $hash, 0);
    return undef;
}

1;

=pod

=begin html

    <p>
      <a name="EntryComIP" id="EntryComIP"></a>
    </p>
    <h3>
      EntryComIP
    </h3>
    <ul>
      <li>Provides handling of 2n(R) EntryCom IP devices (<a href="http://www.2n.cz" target="_blank">vendor website</a>):<br>
      <br>
      </li>
      <li>
        <a name="EntryComIPdefine" id="EntryComIPdefine"></a> <b>Define</b>
        <div style="margin-left: 2em">
          <code>define &lt;name&gt; EntryComIP &lt;ip&gt;</code><br>
          <br>
          Example:
          <div style="margin-left: 2em">
            <code>define AudioKit EntryComIP 192.168.178.21</code><br>
          </div><br>
        </div><a name="EntryComIPset" id="EntryComIPset"></a> <b>Set</b>
        <ul>
          <li>
            <b>audioTest</b> will start the Audio Test
          </li>
          <li>
            <b>clear</b> &nbsp;&nbsp;readings&nbsp;&nbsp; can be used to cleanup auto-created readings from deprecated devices.
          </li>
          <li>
            <b>getAll</b> Fetches all available information from the device. This is a shortcut for all the following get methods.
          </li>
          <li>
            <b>getInfo</b> Fetches only system info from the device.
          </li>
          <li>
            <b>getStatus</b> Fetches status info from the device. Mainly times.
          </li>
          <li>
            <b>getIoCaps</b> Fetches the available io ports. Only the existence.
          </li>
          <li>
            <b>getIoStauts</b> Fetches the available io ports. Only the status.
          </li>
          <li>
            <b>ioCtrl</b> Controls the outputs. E.g. "set AudioKit ioCtrl led1 on"
          </li>
          <li>
            <b>password</b> Sets the password for the device user.
          </li>
          <li>
            <b>restart</b> Restarts the device.
          </li>
          <li>
            <b>trigger</b> Trigger an automation event (more information in the <a href="https://wiki.2n.cz/download/attachments/23102595/2N_Helios_IP_Automation_Manual_EN_2.14.pdf" target="_blank">automation manual</a>. See Event.HttpTrigger)
          </li>
          <li>
            <b>subscribeLog</b> Subscribes to the event stream. This is for debugging only. The module will automatically take care about the subscription.
          </li>
          <li>
            <b>unsubscribeLog</b> Unsubscribes from the event stream. This is for debugging only. The module will automatically take care about the subscription.
          </li>
        </ul><br>
        <br>
        <a name="EntryComattr" id="EntryComattr"></a> <b>Attributes</b><br>
        <br>
        <ul>
          <li><b>ip</b>: The IP of the 2n device
          </li>
          <li><b>ignoreSslErrors</b>: Set to 1 in order to ignore certificate errors. (This is needed if you use the broken default certificate)</li>
          <li><b>pollTimeout</b>: The event stream uses HTTP long polling. This is the time in seconds how long a poll will last. No need to change it unless you have problems with your network setup.
          </li>
        </ul><br>
        <br>
        <b>Additional information</b><br>
        <br>
        <ul>
          <li>Basically all Helios IP Devices are supported: Verso, Force, Safety, Vario, Uni, Audio Kit, Video Kit.</li>
          <li>Features: Read System information, control and read in- and output states, receive live events from the device.</li>
          <li>Events supported currently: OutputChanged, InputChanged.</li>
          <li>Your device should use firmware 2.14+.</li>
          <li>Module is based on the HTTP-API: <a href="https://wiki.2n.cz/download/attachments/23102595/2N_Helios_IP_HTTP_API_Manual_EN_2.14.pdf">HTTP-API manual</a></li>
          <li>Integration license is required for that module. Other licenses are optional.</li>
          <li>You must create a user for fhem on your 2n device. Do not forget to grant permissions to the user.</li>
          </ul>
      </li>
    </ul>

=end html

=cut
