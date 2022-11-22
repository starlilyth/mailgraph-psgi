#!/usr/bin/env plackup

# mailgraph -- postfix mail traffic statistics
# copyright (c) 2000-2007 ETH Zurich
# copyright (c) 2000-2007 David Schweikert <david@schweikert.ch>
# released under the GNU General Public License
# Plack-ified by Lily Star <github.com/starlilyth>

use strict;
use warnings;
use RRDs;
use POSIX qw(uname);
use Plack::Request;

my $rrd_dir = '/var/log/mailgraph'; # path to where the RRD databases are
my $tmp_dir = '/tmp'; # temporary directory where the images are stored

my $VERSION = "2.0";
my $host = (POSIX::uname())[1];
my $scriptname = 'mailgraph.psgi';
my $xpoints = 540;
my $points_per_sample = 3;
my $ypoints = 160;
my $ypoints_err = 96;
my $rrd = "$rrd_dir/mailgraph.rrd";
my $rrd_virus = "$rrd_dir/mailgraph_virus.rrd";
my $content;

my @graphs = (
	{ title => 'Last Day',   seconds => 3600*24,        },
	{ title => 'Last Week',  seconds => 3600*24*7,      },
	{ title => 'Last Month', seconds => 3600*24*31,     },
	{ title => 'Last Year',  seconds => 3600*24*365, },
);

my %color = (
	sent     => '000099', # rrggbb in hex
	received => '009900',
	rejected => 'AA0000', 
	bounced  => '000000',
	virus    => 'DDBB00',
	spam     => '999999',
);

sub rrd_graph(@)
{
	my ($range, $file, $ypoints, @rrdargs) = @_;
	my $step = $range*$points_per_sample/$xpoints;
	# choose carefully the end otherwise rrd will maybe pick the wrong RRA:
	my $end  = time; $end -= $end % $step;
	my $date = localtime(time);
	$date =~ s|:|\\:|g unless $RRDs::VERSION < 1.199908;

	my ($graphret,$xs,$ys) = RRDs::graph($file,
		'--imgformat', 'PNG',
		'--width', $xpoints,
		'--height', $ypoints,
		'--start', "-$range",
		'--end', $end,
		'--vertical-label', 'msgs/min',
		'--lower-limit', 0,
		'--units-exponent', 0, # don't show milli-messages/s
		'--lazy',
		'--color', 'SHADEA#ffffff',
		'--color', 'SHADEB#ffffff',
		'--color', 'BACK#ffffff',

		$RRDs::VERSION < 1.2002 ? () : ( '--slope-mode'),

		@rrdargs,

		'COMMENT:['.$date.']\r',
	);

	my $ERR=RRDs::error;
	die "ERROR: $ERR\n" if $ERR;
}

sub graph($$)
{
	my ($range, $file) = @_;
	my $step = $range*$points_per_sample/$xpoints;
	rrd_graph($range, $file, $ypoints,
		"DEF:sent=$rrd:sent:AVERAGE",
		"DEF:msent=$rrd:sent:MAX",
		"CDEF:rsent=sent,60,*",
		"CDEF:rmsent=msent,60,*",
		"CDEF:dsent=sent,UN,0,sent,IF,$step,*",
		"CDEF:ssent=PREV,UN,dsent,PREV,IF,dsent,+",
		"AREA:rsent#$color{sent}:Sent    ",
		'GPRINT:ssent:MAX:total\: %8.0lf msgs',
		'GPRINT:rsent:AVERAGE:avg\: %5.2lf msgs/min',
		'GPRINT:rmsent:MAX:max\: %4.0lf msgs/min\l',

		"DEF:recv=$rrd:recv:AVERAGE",
		"DEF:mrecv=$rrd:recv:MAX",
		"CDEF:rrecv=recv,60,*",
		"CDEF:rmrecv=mrecv,60,*",
		"CDEF:drecv=recv,UN,0,recv,IF,$step,*",
		"CDEF:srecv=PREV,UN,drecv,PREV,IF,drecv,+",
		"LINE2:rrecv#$color{received}:Received",
		'GPRINT:srecv:MAX:total\: %8.0lf msgs',
		'GPRINT:rrecv:AVERAGE:avg\: %5.2lf msgs/min',
		'GPRINT:rmrecv:MAX:max\: %4.0lf msgs/min\l',
	);
}

sub graph_err($$)
{
	my ($range, $file) = @_;
	my $step = $range*$points_per_sample/$xpoints;
	rrd_graph($range, $file, $ypoints_err,
		"DEF:bounced=$rrd:bounced:AVERAGE",
		"DEF:mbounced=$rrd:bounced:MAX",
		"CDEF:rbounced=bounced,60,*",
		"CDEF:dbounced=bounced,UN,0,bounced,IF,$step,*",
		"CDEF:sbounced=PREV,UN,dbounced,PREV,IF,dbounced,+",
		"CDEF:rmbounced=mbounced,60,*",
		"AREA:rbounced#$color{bounced}:Bounced ",
		'GPRINT:sbounced:MAX:total\: %8.0lf msgs',
		'GPRINT:rbounced:AVERAGE:avg\: %5.2lf msgs/min',
		'GPRINT:rmbounced:MAX:max\: %4.0lf msgs/min\l',

		"DEF:virus=$rrd_virus:virus:AVERAGE",
		"DEF:mvirus=$rrd_virus:virus:MAX",
		"CDEF:rvirus=virus,60,*",
		"CDEF:dvirus=virus,UN,0,virus,IF,$step,*",
		"CDEF:svirus=PREV,UN,dvirus,PREV,IF,dvirus,+",
		"CDEF:rmvirus=mvirus,60,*",
		"STACK:rvirus#$color{virus}:Viruses ",
		'GPRINT:svirus:MAX:total\: %8.0lf msgs',
		'GPRINT:rvirus:AVERAGE:avg\: %5.2lf msgs/min',
		'GPRINT:rmvirus:MAX:max\: %4.0lf msgs/min\l',

		"DEF:spam=$rrd_virus:spam:AVERAGE",
		"DEF:mspam=$rrd_virus:spam:MAX",
		"CDEF:rspam=spam,60,*",
		"CDEF:dspam=spam,UN,0,spam,IF,$step,*",
		"CDEF:sspam=PREV,UN,dspam,PREV,IF,dspam,+",
		"CDEF:rmspam=mspam,60,*",
		"STACK:rspam#$color{spam}:Spam    ",
		'GPRINT:sspam:MAX:total\: %8.0lf msgs',
		'GPRINT:rspam:AVERAGE:avg\: %5.2lf msgs/min',
		'GPRINT:rmspam:MAX:max\: %4.0lf msgs/min\l',

		"DEF:rejected=$rrd:rejected:AVERAGE",
		"DEF:mrejected=$rrd:rejected:MAX",
		"CDEF:rrejected=rejected,60,*",
		"CDEF:drejected=rejected,UN,0,rejected,IF,$step,*",
		"CDEF:srejected=PREV,UN,drejected,PREV,IF,drejected,+",
		"CDEF:rmrejected=mrejected,60,*",
		"LINE2:rrejected#$color{rejected}:Rejected",
		'GPRINT:srejected:MAX:total\: %8.0lf msgs',
		'GPRINT:rrejected:AVERAGE:avg\: %5.2lf msgs/min',
		'GPRINT:rmrejected:MAX:max\: %4.0lf msgs/min\l',

	);
}

sub print_html()
{
	$content = <<HEADER;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>Mail statistics for $host</title>
<meta http-equiv="Refresh" content="300" />
<meta http-equiv="Pragma" content="no-cache" />
<style>
*     { margin: 0; padding: 0 }
body  { width: 630px; background-color: white;
	font-family: sans-serif;
	font-size: 12pt;
	margin: 5px }
h1    { margin-top: 20px; margin-bottom: 30px;
        text-align: center }
h2    { background-color: #ddd;
	padding: 2px 0 2px 4px }
hr    { height: 1px;
	border: 0;
	border-top: 1px solid #aaa }
table { border: 0px; width: 100% }
img   { border: 0 }
a     { text-decoration: none; color: #00e }
a:hover  { text-decoration: underline; }
#jump    { margin: 0 0 10px 4px }
#jump li { list-style: none; display: inline;
           font-size: 90%; }
#jump li:after            { content: "|"; }
#jump li:last-child:after { content: ""; }
</style>
</head>
<body>
HEADER

	$content .= "<h1>Mail statistics for $host</h1>\n";

	$content .= "<ul id=\"jump\">\n";
	for my $n (0..$#graphs) {
		$content .= "  <li><a href=\"#G$n\">$graphs[$n]{title}</a>&nbsp;</li>\n";
	}
	$content .= "</ul>\n";

	for my $n (0..$#graphs) {
		$content .=  "<h2 id=\"G$n\">$graphs[$n]{title}</h2>\n";
		$content .=  "<p><img src=\"$scriptname?${n}-n\" alt=\"mailgraph\"/><br/>\n";
		$content .=  "<img src=\"$scriptname?${n}-e\" alt=\"mailgraph\"/></p>\n";
	}

	$content .=  <<FOOTER;
<hr/>
<table><tr><td>
<a href="http://mailgraph.schweikert.ch/">Mailgraph</a>
originally by <a href="http://david.schweikert.ch/">David Schweikert</a></td>
<td align="right">
<!-- <a href="http://oss.oetiker.ch/rrdtool/"><img src="http://oss.oetiker.ch/rrdtool/.pics/rrdtool.gif" alt="" width="120" height="34"/></a> -->
</td>
</tr><tr>
<td>PSGI version $VERSION by <a href="https://github.com/starlilyth/mailgraph-psgi">Lily Star</a></td>
<td></td></tr>
</table>
</body></html>
FOOTER

	return $content;
}

sub send_image($)
{
	my ($file)= @_;
	my $size = -s $file;
	open(IMG, $file) or die;
	my $data;
	$content = $data while read(IMG, $data, $size)>0;
	return $content;
}

sub main($$)
{
	my ($req_uri, $qry_str) = @_;
	my $uri = $req_uri || '';
	$uri =~ s/\/[^\/]+$//;
	$uri =~ s/\//,/g;
	$uri =~ s/(\~|\%7E)/tilde,/g;
	mkdir $tmp_dir, 0755 unless -d $tmp_dir;
	mkdir "$tmp_dir/$uri", 0755 unless -d "$tmp_dir/$uri";
	my $img = $qry_str;
	if(defined $img and $img =~ /\S/) {
		if($img =~ /^(\d+)-n$/) {
			my $file = "$tmp_dir/$uri/mailgraph_$1.png";
			graph($graphs[$1]{seconds}, $file);
			send_image($file);
		}
		elsif($img =~ /^(\d+)-e$/) {
			my $file = "$tmp_dir/$uri/mailgraph_$1_err.png";
			graph_err($graphs[$1]{seconds}, $file);
			send_image($file);
		}
		else {
			die "ERROR: invalid argument\n";
		}
	}
	else {
		print_html;
	}
}

my $app = sub {
  my $env = shift;
  my $req = Plack::Request->new($env);
  my $req_uri = $req->request_uri;
  my $qry_str = $req->query_string;
  main($req_uri, $qry_str);
  my $res = $req->new_response(200);
  if(defined $qry_str and $qry_str =~ /\S/) {
	  $res->content_type('image/png');
  }
  else {
	  $res->content_type('text/html');
  }
  $res->body($content);
  return $res->finalize;
};
