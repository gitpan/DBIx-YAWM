###################################################
## YAWM.pm
## Andrew N. Hicox <andrew@hicox.com>
## http://www.hicox.com
##
## Yet Annother Wrapper Module
## Handy tools for talking to databases
###################################################


## Global Stuff ###################################
  package DBIx::YAWM;
  use 5.6.0;
  use warnings;

  require Exporter;
  use AutoLoader qw(AUTOLOAD);
  
## Class Global Values ############################ 
  our @ISA = qw(Exporter);
  our $VERSION = '2.2.1';
  our $errstr = ();
  our @EXPORT_OK = ($VERSION, $errstr);


## new ############################################
 sub new {
    #local vars
     my %p = @_;
     my $obj = bless ({});
    #you must at least, include Server, User, Pass, and DBType
     unless (
         (exists ($p{Server})) &&
         (exists ($p{User}))   &&
         (exists ($p{Pass}))   &&
         (exists ($p{DBType})) 
     ){
         $errstr = "Server, User, Pass, and DBType are required options to New";
         return (undef);
     }
    #if it's Oracle, we'll be needing a SID too
     if (($p{DBType} eq "Oracle") && (! exists ($p{SID}))){
         $errstr = "SID is a required option for DBType Oracle";
         return (undef);
     }
    #add in anything which might have been sent in
     foreach (keys %p){ $obj->{$_} = $p{$_}; }
    #default values
     $obj->{'LongReadLen'} = 15000 unless (exists($obj->{'LongReadLen'}));
     $obj->{'LongTruncOk'} = 0 unless (exists($obj->{'LongTruncOk'}));
    #login to database
     unless ($obj->Login()){
         $errstr = $obj->{errstr};
         return (undef);
     }
    #return object
     return ($obj);
 }


## Login ##########################################
 sub Login {
    #local vars
     my $self = shift();
     my %p = @_;
     my ($connect_str) = ();
    #are we already logged in?
     if (exists ($self->{dbh})){ return (1); }
    #require appropriate dbi module
     my $mod = "DBD\::$self->{DBType}";
     eval "require $mod";
     if ($@){
         $self->{'errstr'} = "Login: failed to load DBD module $mod: $@";
         return (undef);
     }
    #wow, a "connection string" ... 
     if ($self->{DBType} eq "Sybase"){
         $connect_str = "dbi:Sybase:server=$self->{Server}";
     }elsif ($self->{DBType} eq "Oracle"){
        #if we have a port number we could give that too
         if (exists($self->{Port})){
             $connect_str = "dbi:Oracle:host=$self->{Server};sid=$self->{SID};port=$self->{Port}";
         }else{
             $connect_str = "dbi:Oracle:host=$self->{Server};sid=$self->{SID}";
         }
     }else{
        #wow this is really ghetto
         $self->{errstr} = "Sorry Dude, ";
         $self->{errstr}.= "I don't know how to make connection strings for this DBType ";
         $self->{errstr}.= "someone needs to edit YAWM.pm";
         return (undef);
     }
    #make the connection
     unless ($self->{dbh} = DBI->connect(
         $connect_str,
         $self->{User},
         $self->{Pass}
     )){
         $self->{errstr} = "Login failed: $DBI::errstr";
         return (undef);
     }
    #go ahead and set LongReadLen and LongTruncOk
     $self->{dbh}->{'LongReadLen'} = $self->{'LongReadLen'};
     $self->{dbh}->{'LongTruncOk'} = $self->{'LongTruncOk'};
    #it's all good baby bay bay ...
     return (1);
 }


## Destroy ########################################
 sub Destroy {
    my $self = shift;
    $self->{dbh}->disconnect;
    $self = undef;
 }
 

## True for perl include ##########################
 1;
__END__
## AutoLoaded Methods


## Query ##########################################
sub Query {
    #local vars
     my $self = shift();
     my %params = @_;
     my ($QUERY,$sth,@data,$rec_count,@OUT) = ();
    #check input for required data
     if (
         (! exists ($params{'Select'})) ||
         (! exists ($params{'From'}))
     ){
         $self->{errstr} = "Query missing required data.";
         return (undef);
     }
    #check that -Select is an array ref
     if (ref($params{'Select'}) ne "ARRAY"){
         $self->{errstr} = "Query: Select must be an array reference";
         return (undef);
     }
    #if not logged into db, do it now
     unless ($self->Login()){
         $self->{errstr} = "Login failed $self->{errstr}";
         return (undef);
     }
    #make a query string
     my $select_str = join (", ", @{$params{'Select'}});
     if (exists($params{'Where'})){
         $QUERY = "select $select_str from $params{'From'} where $params{'Where'}";
     }else{
         $QUERY = "select $select_str from $params{'From'}";
     }
    #prepare the query
     if ($self->{'Debug'} > 1){ print "[Query]: preparing query ...\n"; }
     if ($self->{'Debug'} > 1){ print "[Query]:\t $QUERY\n"; }
     unless ($sth = $self->{dbh}->prepare($QUERY)){
         $self->{errstr} = "Query: failed prepare: $QUERY / $DBI::errstr";
         return (undef);
     }
    #execute the query
     if ($self->{'Debug'} > 1){ print "[Query]: executing query ...\n"; }
     unless ($sth->execute()){
         $self->{errstr} = "[Query]: FATAL ERROR / can't execute query $QUERY / $DBI::errstr";
         return (undef);
     }
    #fetch the records
     if ($self->{'Debug'} > 1){ print "[Query]: fetching records ...\n"; }
     while (@data = $sth->fetchrow_array()){
         $rec_count ++;
         my $count = -1;
         my %hash = ();
         foreach (@data){
             $count ++;
             $hash{$params{'Select'}->[$count]} = $_;
         }
         push (@OUT,\%hash);
     }
     $sth->finish();
    #make sure we got something
     if (! $rec_count){
         if ($self->{'Debug'}){ print "[Query]: no records returned\n"; }
         $self->{errstr} = "no records returned";
         return (undef);
     }else{
         if ($self->{'Debug'}){ print "[Query]: recieved $rec_count records\n"; }
         return (\@OUT);
     }
}


## Insert #########################################
 ##insert a record into the given table of the 
 ##database. 
sub Insert {
    #local vars
     my ($self, %p) = @_;
     my (@vals,$sth) = ();
    #requried options
     unless (
         (exists($p{Insert})) &&
         (exists($p{Into}))
     ){
         $self->{errstr} = "Insert and Into are required options to Insert";
         return(undef);
     }
    #proctecting against disaster
     unless ($self->{CanInsert}){
         $self->{errstr} = "The CanInsert option was not set in this object at creation ";
         $self->{errstr}.= "you may not use the Insert method on this object.";
         return (undef);
     }
    #filters
     foreach (keys %{$p{Insert}}){
        #don't insert null values
         unless (length($p{Insert}->{$_})  > 0){
             delete($p{Insert}->{$_});
             next;
         }
        #escape " 's
         $p{Insert}->{$_} =~s/\"/\"\"/g;
     }
    #formulate the sql
     my $field_names = join (', ', sort (keys %{$p{Insert}}));
     foreach (sort (keys %{$p{Insert}})){
         if (exists ($p{Ints}->{$_})){
             push (@vals, "$p{Insert}->{$_}");
         }else{
             push (@vals, "\"$p{Insert}->{$_}\"");
         }
     }
     my $field_values = join (', ',@vals);
     my $sql = "INSERT INTO $p{Into} ($field_names) VALUES ($field_values)";
    #prepare the statement
     if ($self->{'Debug'} > 1){ print "[Insert]: preparing query ...\n"; }
     if ($self->{'Debug'} > 1){ print "[Insert]:\t $sql"; }
     unless ($sth = $self->{dbh}->prepare($sql)){
         $self->{errstr} = "Insert: failed prepare: $sql / $DBI::errstr";
         return (undef);
     }
    #execute insert
     if ($self->{'Debug'} > 1){ print "[Insert]: executing insert ...\n"; }
     unless ($sth->execute()){
         $self->{errstr} = "[Insert]: FATAL ERROR / can't execute insert $sql / $DBI::errstr";
         return (undef);
     }
     $sth->finish();
    #well it must be all-good
     return (1);
}


## Do #############################################
## prepare and execute an SQL statement of no
## particular type. If errors are encountered undef is
## returned and errors go on $obj->{errstr} as usual
## if successfull, whatever is returned from dbi->execute
## is returned here
sub Do {
    #local vars
     my ($self, %p) = @_;
    #required options
     unless (exists($p{SQL})){
         $self->{'errstr'} = "[Do]: SQL is a required option to Do";
         return (undef);
     }
    #prepare statement
     warn ("[Do]: (prepare): $p{SQL}") if $self->{'Debug'};
     $sth = $self->{dbh}->prepare($p{SQL}) || do {
         $self->{'errstr'} = "[Do]: failed to prepare SQL ($p{SQL}): $DBI::errstr";
         warn ($self->{'errstr'}) if $self->{'Debug'};
         return (undef);
     };
     warn ("[Do]: (executing)") if $self->{'Debug'};
     my $res = $sth->execute() || do {
         $self->{'errstr'} = "[Do]: failed to execute SQL ($p{SQL}): $DBI::errstr";
         warn ($self->{'errstr'}) if $self->{'Debug'};
         return (undef);
     };
     $sth->finish();
     return ($res);
}
