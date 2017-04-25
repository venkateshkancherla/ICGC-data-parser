#! /usr/bin/perl

package GetMutationContextDistribution;
use Exporter qw'import';
	our @EXPORT = qw'';

#=====================================================================

our $doc_str = <<END;

Usage: ./locate_in_genome.pl [--in=<file>] [--out=<outfile>] [--help]

============================
 Locate mutations in genome
============================

Queries the Ensembl database about the genomic context of each mutation in the input.
The input is a VCF file in the format of the ICGC SSM file.
The program assigns each mutation with one of the next labels: 
INTERGENIC, EXONIC:#, NON-CODING-EXONIC, INTRONIC. Where the '#' stands for
the *phase* understood as the position in the codon, and can be 0, 1 or 2.

Command-line arguments:

	-i, --in
		Name of the input file.
		If not present, input from standard input.

	-o, --out
		Name of the output file.
		If not present output to standard output.

	-h, --help
		Show this text and exit.

Author: Andrés García García @ Dic 2016.

END


use ICGC_Data_Parser::Ensembl qw(:genome);
use ICGC_Data_Parser::SSM_Parser qw(:parse);
use ICGC_Data_Parser::Tools qw(:general_io uniq :debug);

__PACKAGE__->main( @ARGV ) unless caller();

#===============>> BEGINNING OF MAIN ROUTINE <<=====================
sub main
{
	# Get class
	my $self = shift;
	
	parse_SSM_file(\@_,
		# Dispatch table
		{			
			# Collect the mutation recurrence data
			MATCH	=>	\&assemble_context_distribution,
			
			# Print the resulting data
			END	=>	\&print_context_distribution,
			
			# Print help and exit
			HELP	=>	sub { print_and_exit $doc_str }
		}
	);
}#===============>> END OF MAIN ROUTINE <<=====================


#	===========
#	Subroutines
#	===========

sub assemble_context_distribution
{
	my $cxt = shift(); # Get context (READ/WRITE)
	
	# Create a distribution if not created yet
	$cxt->{DISTRIBUTION} //= {};
	
	# Get relevant context variables
	my $distribution = $cxt->{DISTRIBUTION};
	
	my %opts = %{ $cxt->{OPTIONS} };
	
	# Get context data
	my %context_data = %{ get_mutation_context({
				line => $cxt->{LINE},
				headers => $cxt->{HEADERS},
				gene => $cxt->{OPTIONS}->{gene},
				project => $cxt->{OPTIONS}->{project},
				offline => $cxt->{OPTIONS}->{offline}
			}
		)
	};
	
	# Assemble distribution
	my $relative_position = $context_data{RELATIVE_POSITION};
	$distribution->{$relative_position}++;
}


sub get_mutation_context
{
	# Get arguments
	my %args = %{ shift() };

	# Parse the mutation data
	my %mutation = %{ parse_mutation(\%args) };
	#tweet \%mutation;

	# Assemble output
	my $pos_GRCh38 = map_GRCh37_to_GRCh38( $mutation{'CHROM'}, $mutation{'POS'}, 1 )->[0];
	
	my $projects = join( ',', 
						 map { $_->{project_code} } @{ $mutation{INFO}->{OCCURRENCE} } 
					);
	
	my $consequences = join( ',', 
							uniq
								map { "$_->{gene_affected}($_->{gene_symbol}):$_->{consequence_type}" } 
									grep { $_ -> {gene_affected} }
										@{ $mutation{INFO}->{CONSEQUENCE} } 
						);
	
	my $slice = fetch_slice($mutation{CHROM}, $pos_GRCh38, 1);
	my $overlapping = $slice -> get_all_Genes();
	
	my $overlapped_genes = join( ',', 
								 map {	get_Gene_print_data($_) }
									@{ $overlapping }
							);
	
	my $relative_position = get_gene_context({SLICE => $slice, OVERLAPPING_GENES => $overlapping});
	
	return {
		MUTATION_ID	=>	$mutation{ID},
		MUTATION	=>	$mutation{INFO}->{mutation},
		POSITION_GRCh37	=>	"chr$mutation{CHROM}:$mutation{POS}",
		POSITION_GRCh38	=>	"chr$mutation{CHROM}:$pos_GRCh38",
		RELATIVE_POSITION	=>	$relative_position,
		OVERLAPPED_GENES	=>	$overlapped_genes,
		'CONSEQUENCE(S)'	=>	$consequences,
		'PROJECT(S)'	=>	$projects
	};
}#-----------------------------------------------------------

sub print_header
{
	my %context = %{ shift() }; # Get context (READ ONLY)
	
	# Get relevant context variables
	my ($project, $gene, $output, $output_fields) 
		= @context{qw(PROJECT GENE OUTPUT OUTPUT_FIELDS)};

	# Print heading lines
	print  $output "# Project: $project->{str}\tGene: $gene->{str}\n";
	print  $output join( "\t", @$output_fields)."\n";
}#-----------------------------------------------------------

sub print_context_distribution
{
	my %context = %{ shift() }; # Get context (READ ONLY)
	
	# Get relevant context variables
	my ($distribution, $output) = @context{qw'DISTRIBUTION OUTPUT'};
	
	## OUTPUT

	# Assemble output fields
	$context{OUTPUT_FIELDS} = [qw(RELATIVE_POSITION RELATIVE_POSITION_COUNT)];
	print_header(\%context);

	my %output = ();
	foreach my $key (sort {$a <=> $b} keys %$distribution){
		# Assemble output
		$output{RELATIVE_POSITION} = $key;
		$output{RELATIVE_POSITION_COUNT} = $distribution->{$key};
	}
	print_fields($output, \%output, $context{OUTPUT_FIELDS});

}#-----------------------------------------------------------

1; 