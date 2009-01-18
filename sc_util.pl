#!/usr/bin/perl

use Device::SerialPort;
use Gtk2 '-init'; # auto-initializes Gtk2
use Glib;
use Gtk2::GladeXML;

my $dir="";

die "usage: $0 /dev/tty..." if not defined($ARGV[0]);

my $device = tie(*FH, "Device::SerialPort", $ARGV[0]) or die "open failed";
$device->baudrate(9600) or die "baudrate failed";
$device->parity("even") or die "parity failed";
$device->databits(8) or die "databits failed";
$device->stopbits(2) or die "stopbits failed";
$device->handshake("none") or die "handshake failed";
$device->rts_active(0) or die "RTS failed";
$device->write_settings or die "cannot write serial settings";

my $w = Glib::IO->add_watch(fileno(FH), 'in', \&read_cb) or die "cannot watch device!";

my $glade = Gtk2::GladeXML->new("sc_util.glade");

$glade->signal_autoconnect_from_package('main');

my $hex_in = $glade->get_widget('entry1');
my $editor = $glade->get_widget('textview1');
my $buffer = $editor->get_buffer();

my $skip=0;

Gtk2->main;

exit 0;

sub append {
    my $newdir=shift;
    my $text = shift;    
    my $end = $buffer->get_end_iter();

    if ($newdir ne $dir) {
	$dir = $newdir;
	$text = "\n$dir $text";
    }

    $buffer->insert($end,$text);
    $end = $buffer->get_end_iter();
    $editor->scroll_to_iter($end,0,0,0,0);
}

sub bin_to_hex {
    my $text;
    my $cnt;
    my $res=shift;
    my $buf=shift;

    for($cnt=0;$cnt<$res;$cnt++) {
	$text = $text . sprintf("%02x ",ord(substr($buf,$cnt,1)));
    }

    return $text;    
}

sub hex_to_bin {
    my $res;
    $_=shift;
    chomp;
    @_=split(/\s+/,$_);
    foreach(@_) {
	$res = $res.chr(hex($_));
    }
    return $res;
}

sub read_cb {
    my $res, $buf;
    
    if($skip>0) {
	($res,$buf)=$device->read($skip);
	$skip-=$res;
	return 1;
    }
    
    ($res,$buf)=$device->read(255);
    
    #print "$res $buf\n";    
    
    append("<",bin_to_hex($res,$buf));
    
    return 1;
}

sub entry1_activate_cb {
    my $bin=hex_to_bin($hex_in->get_text());
    $hex_in->set_text("");
    append(">",bin_to_hex(length($bin),$bin));
    $device->write($bin);
    $skip=length($bin);
}

sub btn_reset_clicked_cb {
    append(">","RESET ");
    $device->pulse_rts_on(50);
}

sub window1_destroy_cb {
    Gtk2->main_quit();
}
