requires "DBI" => "0";
requires "Eval::Closure" => "0";
requires "File::Slurp::Tiny" => "0";
requires "File::Temp" => "0";
requires "Log::Dispatch" => "0";
requires "Log::Dispatch::TestDiag" => "0";
requires "Moose" => "0";
requires "Moose::Role" => "0";
requires "Moose::Util::TypeConstraints" => "0";
requires "MooseX::Getopt::Dashes" => "0";
requires "MooseX::Types" => "0";
requires "MooseX::Types::Combine" => "0";
requires "MooseX::Types::Moose" => "0";
requires "MooseX::Types::Path::Class" => "0";
requires "Path::Class" => "0";
requires "Test::Fatal" => "0";
requires "Test::More" => "0.96";
requires "namespace::autoclean" => "0";
requires "parent" => "0";
requires "strict" => "0";
requires "warnings" => "0";

on 'test' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "File::Spec" => "0";
  requires "Test::More" => "0.96";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "2.120900";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "0";
};

on 'develop' => sub {
  requires "Code::TidyAll" => "0.24";
  requires "File::Spec" => "0";
  requires "IO::Handle" => "0";
  requires "IPC::Open3" => "0";
  requires "Perl::Critic" => "1.123";
  requires "Perl::Tidy" => "20140711";
  requires "Pod::Coverage::TrustPod" => "0";
  requires "Test::CPAN::Changes" => "0.19";
  requires "Test::Code::TidyAll" => "0.24";
  requires "Test::EOL" => "0";
  requires "Test::More" => "0.88";
  requires "Test::NoTabs" => "0";
  requires "Test::Pod" => "1.41";
  requires "Test::Pod::Coverage" => "1.08";
  requires "Test::Pod::LinkCheck" => "0";
  requires "Test::Pod::No404s" => "0";
  requires "Test::Spelling" => "0.12";
  requires "Test::Synopsis" => "0";
  requires "Test::Version" => "1";
};
