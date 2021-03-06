#' Combine BEAST log files after removing burnin
#'
#" Additionally, if some BEAST runs converged to a different tree space with different posterior, will exclude log files from runs with significantly lower posterior (analysis of variance)
#'
#" @param logfns Vector of log files 
#' @param bunrProportion Will remove this proportion from the beginning of logs
#' @param ofn If not NULL will save the combined log to this file name 
#' @return Data frame with combined logs 
#' @export
combine_logs <- function(logfns, burnProportion = .5 , ofn = NULL ){
	
	Xs <- lapply( logfns, function(fn){
		d = read.table( fn, header=TRUE, stringsAsFactors=FALSE) 
		i <- floor( burnProportion * nrow(d))
		tail( d, nrow(d) - i )
	})

	if ( length( Xs ) > 1 ){
		medlogpos <- sapply( Xs, function(X) median (X$posterior ))
		Xs <- Xs[ order( medlogpos, decreasing=TRUE ) ]
		
		xdf = data.frame(logpo = NULL, logfn = NULL ) 
		k <- 0
		for (X in Xs ){
			k <- k + 1
			xdf <- rbind ( xdf ,  data.frame( logpo = X$posterior , logfn = logfns[k] ) )
		}

		m <- aov(  logpo ~ logfn , data = xdf )
		a <- TukeyHSD( m )
		ps <- sapply( 1:(length(Xs)-1), function(k) {
			a$logfn[ k, 4 ]
		})
		keep <- c( 1, 1 + which ( ps > .05 ) )
		Xs1 <- Xs[ keep ]
		
		cat( "These logs were retained:\n" )
		print( names(Xs1) )

		X <- do.call( rbind, Xs1)
	} else{
		X <- Xs[[1]]
	}
	
	if ( !is.null( ofn ))
		saveRDS(X , file = ofn )
	
	X
}

#' Combine PhyDyn trajectory files after removing burnin
#'
#" @param trajfns Vector of trajectory files. Don't pass low quality BEAST fits; see the combine_logs function for filtering by quality 
#' @param bunrProportion Will remove this proportion from the beginning of logs
#' @param ntraj This integer number of trajectories will be sampled from each trajectory file 
#' @param ofn If not NULL will save the combined trajectory log to this file name 
#' @return Data frame with combined trajectories 
#' @export
combine_traj <- function(trajfns, burnProportion = .50, ntraj = 100, ofn = NULL )
{
	cat( 'NOTE: only pass trajectory fns that pass the quality filter in the combine_logs function\n' )
	Xs <- lapply( trajfns, function(fn){
		d = read.table( fn, header=TRUE, stringsAsFactors=FALSE)
		ids = sort (unique( d$Sample ))
		keep <- sample( tail(ids, floor(length(ids)-burnProportion*length(ids)))
		 , size = ntraj, replace=FALSE)
		d = d[ d$Sample %in% keep , ]
		d$Sample <- paste0( as.character(d$Sample) , '.', fn)
		d
	})
	if ( length( Xs ) == 1)
		X <- Xs[[1]]
	else 
		X <- do.call( rbind, Xs )
	if ( !is.null ( ofn ))
		saveRDS( X, file = ofn )
	
	X
}


# cite:Zwiers, F.W., and H. von Storch: Taking serial correlation into accountin tests of the mean.J. Climate 8:336 351 (1995).
.test.diffpo <- function( x, y )
{ 
	ne = coda::effectiveSize( x ) 
	me = coda::effectiveSize( y ) 
	n = length( x ) 
	m = length( y ) 
	s = sqrt (  sum( sum((x-mean(x))^2) + sum((y-mean(y))^2)  ) / (n + m  -2)  )
	.t = ( mean(y) - mean(x) ) / ( s * (1/sqrt(ne)  +   1/sqrt(me))  )
	#print(.t) 
	#print( c( ne , me ))
	pp = pt( .t , df = ne + me - 2)
	min( pp, 1 - pp )
}


#' Combine BEAST log AND trajectory files after removing burnin
#'
#' Additionally, if some BEAST runs converged to a different tree space with different posterior, will exclude log files from runs with significantly lower posterior (analysis of variance)
#' The 'Sample' column is modified and shared between the combined log and trajectory files so that they can be referenced against eachother
#'
#" @param logfns Vector of log files 
#" @param trajfns Vector of trajectory files. This MUST correspond to the same beast runs in logfns and be in the same order 
#' @param bunrProportion Will remove this proportion from the beginning of logs
#' @param ntraj This integer number of trajectories will be sampled from each trajectory file 
#' @param ofn If not NULL will save the combined log to this file name 
#' @param ofntraj If not NULL will save the combined traj to this file name 
#' @param pth Threshold p value for excluding logs based on sampled posterior values. If <0 will include all logs
#' @return List with with combined logs and traj
#' @export
combine_logs_and_traj <- function(logfns, trajfns, burnProportion = .5 , ntraj = 200, ofn = NULL , ofntraj = NULL, pth = .01){
	if ( length( logfns ) != length( trajfns))
		stop('Provide *paired* log and traj files. These have different length.')
	cat( 'These are the paired log and traj files provided\n')
	print(cbind( logfns, trajfns ))
	cat('****Make sure that these are paired correctly and each row corresponds to the same beast run****\n')
	
	Xs <- lapply( logfns, function(fn){
		d = tryCatch( 
			read.table( fn, header=TRUE, stringsAsFactors=FALSE) 
		, error = function(e) return(NULL))
		if (is.null(d))
			return(NULL)
		i <- floor( burnProportion * nrow(d))
		tail( d, nrow(d) - i )
	})
	keep <- rep(FALSE, length(Xs ))
	keep[ sapply( Xs, is.null) ] <- FALSE
	
	pps = NA 
	if ( length( Xs ) > 1 ){
		medlogpos <- sapply( Xs, function(X) if ( is.null(X)) return(-Inf) else median (X$posterior ))
		i <- which.max( medlogpos )
		pps = sapply( (1:length(Xs)), function(k) {
			if ( is.null( Xs[[k]] ) )
				return(-Inf)
			.test.diffpo( Xs[[i]]$posterior, Xs[[k]]$posterior )
		})
		keep[ pps > pth  ] <- TRUE
		keep <- which(keep )
		for ( k in keep )
			Xs[[k]]$Sample <- paste(sep='.', Xs[[k]]$Sample, k )
		
		X <- do.call( rbind, Xs[keep])
	} else{
		k <- 1
		Xs[[k]]$Sample <- paste(sep='.', Xs[[k]]$Sample, k )
		X <- Xs[[1]]
		keep <- 1
	}
	
	
	
	# save comb log 	
	if ( !is.null( ofn ))
		saveRDS(X , file = ofn )
	
	cat('\n\n')
	cat( 'EFFECTIVE SAMPLE SIZES OF COMBINED LOGS\n')
	print( as.data.frame( unlist( sapply( X, function(x) if(is.numeric( x )) tryCatch(coda::effectiveSize( x ),error=function(e) NA)  )  ) ) )
	cat('\n\n')
	
	# now combine traj 
	Js <- lapply( keep , function(k){
		fn = trajfns[k]
		d = tryCatch( 
			read.table( fn, header=TRUE, stringsAsFactors=FALSE)
		, error = function(e) NULL)
		if (is.null(d))
			return(NULL)
		ids = sort (unique( d$Sample ))
		keepids <- tail(ids, floor(length(ids)-burnProportion*length(ids)))
		keeptraj <- sample( keepids
		 , size = min( length(keepids) , ntraj )
		 , replace=FALSE)
		d = d[ d$Sample %in% keeptraj , ]
		d$Sample <- paste0( as.character(d$Sample) , '.', k)
		d
	})
	if ( length( Js ) == 1)
		J <- Js[[1]]
	else 
		J <- do.call( rbind, Js )
	if ( !is.null ( ofntraj ))
		saveRDS( J, file = ofntraj )
	
	cat( "These logs were retained:\n" )
	print( logfns[keep] )
	cat( "These traj files were retained:\n" )
	print( trajfns[keep] )
	list( log = X, traj = J , medlogpos = medlogpos, keep = keep, pps = pps , Xs = Xs  )
}





#' Automatic generation of metadata.yml
#' You can add more information if you like
#' 
#' @export 
write_phylo_metadata_yaml <- function(
  
  # GENERAL INFO
  
  author = "Lily Geidelberg", # Who did this analysis? 
  location = "weifang",
  model_version = "seijr0.0.0", # Compartmental model version
  
  # What dates do you want the plots to run from and to?
  # NOTE that at the moment plots will start from just after the SEIJR dynamics kick in; the script ignores start_date for now
  start_date = "2020-01-24",
  end_date = "2020-02-24",
  
  
  # SEQUENCE INFO
  
  sequence_downsampling = "none", # "deduplicated" "random"
  
  first_sample = "2020-01-24", # When was the first INTERNAL sample?
  last_sample = "2020-02-10", # When was the last INTERNAL sample?
  internal_seq = 20, # How many regional sequences did you use?
  exog_seq = 33, # How many exogenous sequences did you use?
  
  
  
  # TREE ESTIMATION METHODS
  tree_estimation_method = "free_tree", # "free_node" "fixed_tree"
  
  n_startingtrees = 20, # Number of starting trees
  
  
  # CLOCK MODEL
  init_clock_rate = 0.0015,
  
  # PRIORS
  tree_prior = "PhyDyn_SEIR",
  min_P = 0.01,
  Penalty_Agt_Y = 0,
  
  
  # Pop params
  T0 = 2019.7,
  exog_init_pop = 0.01,
  S = 500, # if estimated, put "estimated"
  b = 15,
  gamma0 = 73,
  gamma1 = 121.667,
  importRate = 5,
  tau = "estimated",
  p_h = "estimated",
  
  Ne = 0.1,
  clock_rate_prior_lower = 0.0005,
  clock_rate_prior_upper = 0.005,
  
  
  # TREE OPERATORS. T = lines were left as is following generation of XML. F = lines removed.
  PhydynSEIRTreeScaler = T,
  PhydynSEIRTreeRootScaler = T,
  PhydynSEIRUniformOperator = T,
  CoalescentConstantWilsonBalding = T,
  CoalescentConstantSubtreeSlide = T,
  CoalescentConstantNarrow = T,
  CoalescentConstantWide = T,
  school_closure_date = NULL,
  lockdown_date = NULL,
  ...
  
) {
  yaml::write_yaml(c(as.list(environment()), list(...)), "metadata.yml")
  return(metadata = c(as.list(environment()), list(...)))
}
#~ write_phylo_metadata_yaml()




#' Sampling distribution of sequences
#' 
#' @param path_to_nex Path to mcc nexus tree
#' @param path_to_save PNG saved here 

plot_sample_distribution = function(path_to_nex, path_to_save = 'sample_distribution.png' ) {
  
  library(tidyr)
  library(dplyr)
  library(ggplot2)
  library(ape)
  
  #parse dates/location 
  nex <- read.nexus(path_to_nex)
  algn3 = data.frame(seq_id = nex$tip.label) %>% 
    separate(seq_id, c("Seq_ID", "Epi", "Date", "Date_2", "Region"), "[|]") %>% 
    mutate(Region = ifelse(Region == "_Il", "Local", "Global")) %>% 
    mutate(Date = as.Date(Date, "%Y-%m-%d"))
  
  pl = ggplot(algn3, aes(x = Date, color= Region, fill = Region)) +
    geom_histogram(aes(y=..density..), position="identity", 
                   alpha=0.5, bins = as.numeric(max(algn3$Date)-min(algn3$Date)) + 1) +
    geom_density(alpha=0.4) + 
    theme_minimal() +
    scale_color_manual(values=c("#999999","#E69F00"))+
    scale_fill_manual(values=c( "#999999", "#E69F00"))+
    labs(x="", y = "Sampling density")
  
  
  if (!is.null(path_to_save))
    ggsave(pl, file = path_to_save)
  
  return(pl)
}

#' Plot sample times for D and G genotypes  on spike 614 
#' 
#' @param s614 data frame produced by compute_spike614genotype, also element $s614 produced by s614_phylodynamics 
#' @export 
plot_sample_distribution_spike614 = function(s614, path_to_save = 'sample_distribution.png' ) 
{
  
  library(tidyr)
  library(dplyr)
  library(ggplot2)
  library(ape)
  
  i <- as.character( s614$s614 ) %in% c( 'G', 'D' )
  X <- data.frame( s614 = as.character( s614[ i, 's614'] ), row.names = rownames(s614 )[i] )
  s614 = X 
  #parse dates/location 
  algn3 = data.frame( Seq_ID = rownames(s614) 
	  , Date = as.numeric( sapply( strsplit( rownames(s614), '\\|'), function(x) tail(x,2)[1] ) )
	  , Genotype = s614$s614 
	)
  
  pl = ggplot(algn3, aes(x = Date, color= Genotype, fill = Genotype)) +
#~     geom_histogram(aes(y=..density..), position="identity", 
#~                    alpha=0.5, bins = as.numeric(max(algn3$Date)-min(algn3$Date)) + 1) +
    geom_density(alpha=0.4) + 
    theme_minimal() +
    scale_color_manual(values=c("#999999","#E69F00"))+
    scale_fill_manual(values=c( "#999999", "#E69F00"))+
    labs(x="", y = "Sampling density")
  
  
  if (!is.null(path_to_save))
    ggsave(pl, file = path_to_save)
  
  return(pl)
}



#' Compute R0, growth rate and doubling time for the SEIJR.0.0 model 
#'
#' Also prints to the screen a markdown table with the results. This can be copied into reports. 
#' The tau & p_h parameters _must_ be in the log files. If that's not the case, you can add fixed values like this: X$seir.tau <- 74; X$seir.p_h <- .2
#'
#" @param X a data frame with the posterior trace, can be produced by 'combine_logs' function
#' @param gamma0 Rate of leaving incubation period ( per capita per year )
#' @param gamma1 Rate of recovery (per capita per year)
#' @return Data frame with tabulated results and CI 
#' @export 
SEIJR_reproduction_number <- function( X, gamma0 = 73, gamma1 = 121.667,precision =3 ) {
	# tau = 74, p_h = 0.20 , 
	cat( 'Double check that you have provided the correct gamma0 and gamma1 parameters\n' )
  
  if(is.null(X$seir.tau))
    X$seir.tau <- 74; 
  
  if(is.null(X$seir.p_h))
    X$seir.p_h <- .2
	
	Rs = ((1-X$seir.p_h)*X$seir.b/gamma1 + X$seir.tau*X$seir.p_h*X$seir.b/gamma1) 
	qR = signif( quantile( Rs, c(.5, .025, .975 )), precision )
	
	# growth rates 
	beta = (1-X$seir.p_h)*X$seir.b + X$seir.p_h*X$seir.tau*X$seir.b
	r = (-(gamma0 + gamma1) + sqrt( (gamma0-gamma1)^2 + 4*gamma0*beta )) / 2
	qr =  signif( quantile( r/365, c( .5, .025, .975 )), precision ) # growth rate per day 
	
	# double times 
	dr = r / 365 
	dbl = log(2) / dr 
	qdbl  = signif( quantile( dbl, c( .5, .025, .975 )), precision ) # days 
	
	#cat ( 'R0\n')
	#print( qR )
	
	O = data.frame( 
	  `Reproduction number` = qR
	  , `Growth rate (per day)` = qr
	  , `Doubling time (days)` = qdbl
	 )
	print( knitr::kable(O) )
	O 
}



#' Plot the cumulative infections through time from a SEIJR trajectory sample
#' 
#" Also computes CIs of various dynamic variables 
#'
#" @param trajdf Either a dataframe or a path to rds containing a data frame with a posterior sample of trajectories (see combine_traj)
#' @param case_data An optional dataframe containing reported/confirmed cases to be plotted alongside estimates. *Must* contain columns 'Date' and 'Cumulative'. Ensure Date is not a factor or character (see as.Date )
#' @param date_limits  a 2-vector containing bounds for the plotting window. If the upper bound is missing, will use the maximum time in the trajectories
#' @param path_to_save Will save a png here 
#' @return a list with derived outputs from the trajectories. The first element is a ggplot object if you want to further customize the figure 
#' @export 
SEIJR_plot_size <- function(trajdf
  , case_data = NULL
  , date_limits = c( as.Date( '2020-02-01'), NA ) 
  , path_to_save='size.png'
  , log_y_axis = F
  , ...
) {
	library( ggplot2 ) 
	library( lubridate )
	
	if (!is.data.frame(trajdf)){
		# assume this is path to a rds 
		readRDS(trajdf) -> trajdf 
	}
	
	#~ 	r <- read.csv( '../seir21.0/weifangReported.csv', header=TRUE , stringsAsFactors=FALSE)
	#~ 	r$Date <- as.Date( r$Date )
	#~ 	r$reported = TRUE
	#~ 	r$`Cumulative confirmed` = r$Cumulative.confirmed.cases

	dfs <- split( trajdf, trajdf$Sample )
	taxis <- dfs[[1]]$t 
	
	if ( is.na( date_limits[2]) )
		date_limits[2] <- as.Date( date_decimal( max(taxis)  ) )

	qs <- c( .5, .025, .975 )

	# infectious
	Il = do.call( cbind, lapply( dfs, '[[', 'Il' ))
	Ih = do.call( cbind, lapply( dfs, '[[', 'Ih' ))
	I = Il + Ih 
	t(apply( I, MAR=1, FUN= function(x) quantile(x, qs ))) -> Ici 

	# cases 
	cases <- do.call( cbind, lapply( dfs, '[[', 'infections' ))
	t(apply( cases, MAR=1, FUN=function(x) quantile(x,qs))) -> casesci 

	#exog 
	exog <- do.call( cbind, lapply( dfs, '[[', 'exog' ))
	t(apply( exog, MAR=1, FUN=function(x) quantile(x, qs )	)) -> exogci 

	#E
	E <- do.call( cbind, lapply( dfs, '[[', 'E' ))
	t(apply( E, MAR=1, FUN=function(x) quantile(x, qs )	)) -> Eci 


	#~ ------------
	pldf <- data.frame( Date = ( date_decimal( taxis ) ) , reported=FALSE )
	pldf$`Cumulative infections` = casesci[,1]
	pldf$`2.5%` = casesci[,2]
	pldf$`97.5%` = casesci[,3] 
	
	if ( !is.null( case_data )){
		case_data$reported = TRUE
		pldf <- merge( pldf, case_data , all = TRUE ) 
	}
	
	pldf <- pldf[ with( pldf, Date > date_limits[1] & Date <= date_limits[2] ) , ]
	pl = ggplot( pldf ) + 
	  geom_path( aes(x = Date, y = `Cumulative infections` , group = !reported), lwd=1.25) + 
	  geom_ribbon( aes(x = Date, ymin=`2.5%`, ymax=`97.5%`, group = !reported) , alpha = .25 ) 
	
	if ( !is.null(case_data) ) {
		if( !(class(case_data$Date)=='Date') ){
			stop('case_data Date variable must be class *Date*, not character, integer, or POSIXct. ') 
		}
		pl <- pl + geom_point( aes( x = Date, y = Cumulative ) ) 
	}
	pl <- pl + theme_minimal()  + xlab('') + 
	 ylab ('Cumulative estimated infections (ribbon) 
	 Cumulative confirmed (points)' )  #+  scale_y_log10()
	
	if(log_y_axis == T)
	  pl <- pl +  scale_y_log10()
	
	if (!is.null(path_to_save))
		ggsave(pl, file = path_to_save)
	
	list(
	 pl = pl
	  , taxis = taxis 
	  , Il = Il
	  , Ih = Ih
	  , E = E 
	  , I = I 
	  , cases = cases 
	  , exog = exog 
	  , pldf =pldf 
	  , case_data = case_data 
	)
}




#' Plot the daily new infections through time from a SEIJR trajectory sample
#' 
#" Also computes CIs of various dynamic variables 
#'
#" @param trajdf Either a dataframe or a path to rds containing a data frame with a posterior sample of trajectories (see combine_traj)
#' @param logdf Either a dataframe or a path to rds containing a data frame with posterior logs
#' @param case_data An optional dataframe containing reported/confirmed cases to be plotted alongside estimates. *Must* contain columns 'Date' and 'Confirmed'. Ensure Date is not a factor or character (see as.Date )
#' @param date_limits  a 2-vector containing bounds for the plotting window. If the upper bound is missing, will use the maximum time in the trajectories
#' @param path_to_save Will save a png here 
#' @return a list with derived outputs from the trajectories. The first element is a ggplot object if you want to further customize the figure 
#' @export 
SEIJR_plot_daily_inf <- function(trajdf
  , logdf
  , case_data = NULL
  , date_limits = c( as.Date( '2020-02-01'), NA ) 
  , path_to_save='daily.png'
  , log_y_axis = F
  , ...
) {
	library( ggplot2 ) 
	library( lubridate )
	
	if (!is.data.frame(trajdf)){
		# assume this is path to a rds 
		readRDS(trajdf) -> trajdf 
	}
	
	if (!is.data.frame( logdf ))
		X <- readRDS(logdf ) else X <- logdf
	
		if(is.null(X$seir.tau))
		  X$seir.tau <- 74; 
		
		if(is.null(X$seir.p_h))
		  X$seir.p_h <- .2
		
	dfs <- split( trajdf, trajdf$Sample )
	taxis <- dfs[[1]]$t 
	
	s <- sapply( dfs, function(df) df$Sample[1] )
	X1 <- X[match( s, X$Sample ), ]
	
	if ( is.na( date_limits[2]) )
		date_limits[2] <- as.Date( date_decimal( max(taxis)  ) )

	qs <- c( .5, .025, .975 )

	# infectious
	Il = do.call( cbind, lapply( dfs, '[[', 'Il' ))
	Ih = do.call( cbind, lapply( dfs, '[[', 'Ih' ))
	I = Il + Ih 
	t(apply( I, MAR=1, FUN= function(x) quantile(x, qs ))) -> Ici 
	
	# daily new inf 
	Y = lapply( 1:length(dfs) , function(k) {
		x = X1[k, ]
		Il = dfs[[k]]$Il
		Ih = dfs[[k]]$Ih
		S = dfs[[k]]$S
		E = dfs[[k]]$E
		R = dfs[[k]]$R
		tau = X1$seir.tau[k]
		p_h = X1$seir.p_h[k] 
		b = X1$seir.b[k]
		y = (1/365) * ( b * Il + b * tau * Ih   ) *  S/ ( S + E + Il + Ih + R )
	})
	Y = do.call( cbind, Y )
	Yci = t(apply( Y, MAR=1, FUN= function(x) quantile(na.omit(x), qs ))) 

	#~ ------------
	pldf <- data.frame( Date = ( date_decimal( taxis ) ) , reported=FALSE )
	pldf$`New infections` = Yci[,1]
	pldf$`2.5%` = Yci[,2]
	pldf$`97.5%` = Yci[,3] 
	
	if ( !is.null( case_data )){
		case_data$reported = TRUE
		pldf <- merge( pldf, case_data , all = TRUE ) 
	}
	
	pldf <- pldf[ with( pldf, Date > date_limits[1] & Date <= date_limits[2] ) , ]
	pl = ggplot( pldf ) + 
	  geom_path( aes(x = Date, y = `New infections` , group = !reported), lwd=1.25) + 
	  geom_ribbon( aes(x = Date, ymin=`2.5%`, ymax=`97.5%`, group = !reported) , alpha = .25 ) 
	
	if ( !is.null(case_data) ) {
		if( !(class(case_data$Date)=='Date') ){
			stop('case_data Date variable must be class *Date*, not character, integer, or POSIXct. ') 
		}
		pl <- pl + geom_point( aes( x = Date, y = Confirmed ) ) 
	}
	pl <- pl + theme_minimal()  + xlab('') + 
	 ylab ('Estimated daily new infections (ribbon) 
	 Daily confirmed cases (points)' )  #+  scale_y_log10()
	
	if(log_y_axis == T)
	  pl <- pl +  scale_y_log10()
	
	if (!is.null(path_to_save))
		ggsave(pl, file = path_to_save)
	
	list(
	 pl = pl
	  , taxis = taxis 
	  , Il = Il
	  , Ih = Ih
	  , Y
	  , pldf =pldf 
	  , case_data = case_data 
	)
}

#' Plot reproduction number through time from a SEIJR trajectory sample
#'
#" @param trajdf Either a dataframe or a path to rds containing a data frame with a posterior sample of trajectories (see combine_traj)
#' @param logdf Either a dataframe or a path to rds containing a data frame with posterior logs
#' @param date_limits  a 2-vector containing bounds for the plotting window. If the upper bound is missing, will use the maximum time in the trajectories
#' @param gamma0 rate of becoming infectious during incubation period
#' @param gamma1 rate of recovery once infectious
#' @param path_to_save Will save a png here 
#' @return a list with derived outputs from the trajectories. The first element is a ggplot object if you want to further customize the figure 
#' @export 
SEIJR_plot_Rt <- function(trajdf
  , logdf
  , gamma0 = 73, gamma1 = 121.667
  , date_limits = c( as.Date( '2020-02-01'), NA ) 
  , path_to_save='Rt.png'
  , ...
) {
	library( ggplot2 ) 
	library( lubridate )
	
	if (!is.data.frame(trajdf)){
		# assume this is path to a rds 
		readRDS(trajdf) -> trajdf 
	}
	
	if (!is.data.frame( logdf ))
		X <- readRDS(logdf ) else X <- logdf
		
		if(is.null(X$seir.tau))
		  X$seir.tau <- 74; 
		
		if(is.null(X$seir.p_h))
		  X$seir.p_h <- .2
	
	dfs <- split( trajdf, trajdf$Sample )
	taxis <- dfs[[1]]$t 
	
	s <- sapply( dfs, function(df) df$Sample[1] )
	X1 <- X[match( s, X$Sample ), ]
	
	if ( is.na( date_limits[2]) )
		date_limits[2] <- as.Date( date_decimal( max(taxis)  ) )

	qs <- c( .5, .025, .975 )
	
	Rs = ((1-X1$seir.p_h)*X1$seir.b/gamma1 + X1$seir.tau*X1$seir.p_h*X1$seir.b/gamma1)

	# infectious
	Il = do.call( cbind, lapply( dfs, '[[', 'Il' ))
	Ih = do.call( cbind, lapply( dfs, '[[', 'Ih' ))
	S = do.call( cbind, lapply( dfs, '[[', 'S' ))
	E = do.call( cbind, lapply( dfs, '[[', 'E' ))
	R = do.call( cbind, lapply( dfs, '[[', 'R' ))
	I = Il + Ih 
	pS <- S / ( S + E + I + R )
	Rts = t(Rs * t(pS))
	t(apply( Rts, MAR=1, FUN= function(x) quantile(na.omit(x), qs ))) -> Yci  
	
#~ browser()
	#~ ------------
	pldf <- data.frame( Date = ( date_decimal( taxis ) ) , reported=FALSE )
	pldf$`R(t)` = Yci[,1]
	pldf$`2.5%` = Yci[,2]
	pldf$`97.5%` = Yci[,3] 
	
	
	pldf <- pldf[ with( pldf, Date > date_limits[1] & Date <= date_limits[2] ) , ]
	pl = ggplot( pldf ) + 
	  geom_path( aes(x = Date, y = `R(t)` , group = !reported), lwd=1.25) + 
	  geom_ribbon( aes(x = Date, ymin=`2.5%`, ymax=`97.5%`, group = !reported) , alpha = .25 ) 
	
	pl <- pl + theme_minimal()  + xlab('') + 
	 ylab ('Eff reproduction number through time' )  #+  scale_y_log10()
	
	if (!is.null(path_to_save))
		ggsave(pl, file = path_to_save)
	
	list(
	 plot = pl
	  , taxis = taxis 
	  , Il = Il
	  , Ih = Ih
	  , Rts
	  , pldf =pldf 
	)
}

#' Plot reporting rate through time from SEIJR trajectory sample and reported cases
#' 
#'
#' @param trajdf Either a dataframe or a path to rds containing a data frame with a posterior sample of trajectories (see combine_traj)
#' @param case_data dataframe containing reported/confirmed cases to be plotted alongside estimates. *Must* contain columns 'Date' and 'Confirmed'. Ensure Date is not a factor or character (see as.Date )
#' @param date_limits  a 2-vector containing bounds for the plotting window. If the upper bound is missing, will use the maximum time in the trajectories
#' @param path_to_save Will save a png here
#' @param errorbar T/F plotting of errorbars on each point
#' @return a list with derived outputs from the trajectories. The first element is a ggplot object if you want to further customize the figure 
#' @export 

SEIJR_plot_reporting <- function(trajdf
                                 , case_data
                                 , date_limits = c( as.Date( '2020-02-01'), NA ) 
                                 , path_to_save='reporting.png'
				 , errorbar = T
                                 , ...
) {
  library( ggplot2 ) 
  library( lubridate )
  library( dplyr )
  
  if (!is.data.frame(trajdf)){
    # assume this is path to a rds 
    readRDS(trajdf) -> trajdf 
  }
  
  dfs <- split( trajdf, trajdf$Sample )
  taxis <- dfs[[1]]$t 
  
  if ( is.na( date_limits[2]) )
    date_limits[2] <- as.Date( date_decimal( max(taxis)  ) )
  
  qs <- c( .5, .025, .975 )
  
  # infectious
  Il = do.call( cbind, lapply( dfs, '[[', 'Il' ))
  Ih = do.call( cbind, lapply( dfs, '[[', 'Ih' ))
  I = Il + Ih 
  t(apply( I, MAR=1, FUN= function(x) quantile(x, qs ))) -> Ici 
  
  # cases 
  cases <- do.call( cbind, lapply( dfs, '[[', 'infections' ))
  t(apply( cases, MAR=1, FUN=function(x) quantile(x,qs))) -> casesci 
  
  #exog 
  exog <- do.call( cbind, lapply( dfs, '[[', 'exog' ))
  t(apply( exog, MAR=1, FUN=function(x) quantile(x, qs )	)) -> exogci 
  
  #E
  E <- do.call( cbind, lapply( dfs, '[[', 'E' ))
  t(apply( E, MAR=1, FUN=function(x) quantile(x, qs )	)) -> Eci 
  
  
  #~ ------------
  pldf <- data.frame( Date = ( date_decimal( taxis ) ) , reported=FALSE )
  pldf$`Cumulative infections` = casesci[,1]
  pldf$`2.5%` = casesci[,2]
  pldf$`97.5%` = casesci[,3] 
  
  if( !(class(case_data$Date)=='Date') ){
    stop('case_data Date variable must be class *Date*, not character, integer, or POSIXct. ') 
  }
  
  case_data$reported = TRUE
  
  pldf <- merge( pldf, case_data , all = TRUE ) 
  pldf <- pldf[ with( pldf, Date > date_limits[1] & Date <= date_limits[2] ) , ]
  pldf$reporting <- lead(pldf$Cumulative, n=1L)/pldf$`Cumulative infections`
  pldf$`rep97.5` <- pmin(lead(pldf$Cumulative, n=1L)/pldf$`2.5%`, 1)
  pldf$`rep2.5` <- lead(pldf$Cumulative, n=1L)/pldf$`97.5%`
  
  pl = ggplot( pldf ) + 
    geom_point(aes(x = Date, y = `reporting`*100, 
                   group = !reported), lwd = 1.25) +
    ylim(0,100) +
    theme_minimal() +
    ylab("% cases reported")
  
  if (errorbar == TRUE)
     pl = pl + geom_errorbar(aes(x = Date, ymin = `rep2.5`*100, ymax = `rep97.5`*100, group = !reported), size=0.8)
  
  if (!is.null(path_to_save))
    ggsave(pl, file = path_to_save)
  
  list(
    pl = pl
    , taxis = taxis 
    , Il = Il
    , Ih = Ih
    , E = E 
    , I = I 
    , cases = cases 
    , exog = exog 
    , pldf =pldf 
    , case_data = case_data 
  )
}



#' Compute R0, growth rate and doubling time for the GMRF or SEIJR model (no difference in this case)
#'
#' Also prints to the screen a markdown table with the results. This can be copied into reports. 
#' The tau & p_h parameters _must_ be in the log files. If that's not the case, you can add fixed values like this: X$seir.tau <- 74; X$seir.p_h <- .2
#'
#" @param X a data frame with the posterior trace, can be produced by 'combine_logs' function
#' @param gamma0 Rate of leaving incubation period ( per capita per year )
#' @param gamma1 Rate of recovery (per capita per year)
#' @return Data frame with tabulated results and CI 
GMRF_SEIJR_reproduction_number <- SEIJR_reproduction_number


#' Plot the cumulative infections through time from a GMRF SEIJR or SEIJR trajectory sample
#' 
#" Also computes CIs of various dynamic variables 
#'
#" @param trajdf Either a dataframe or a path to rds containing a data frame with a posterior sample of trajectories (see combine_traj)
#' @param case_data An optional dataframe containing reported/confirmed cases to be plotted alongside estimates. *Must* contain columns 'Date' and 'Cumulative'. Ensure Date is not a factor or character (see as.Date )
#' @param date_limits  a 2-vector containing bounds for the plotting window. If the upper bound is missing, will use the maximum time in the trajectories
#' @param path_to_save Will save a png here 
#' @return a list with derived outputs from the trajectories. The first element is a ggplot object if you want to further customize the figure 
GMRF_SEIJR_plot_size =  SEIJR_plot_size


#' Plot reporting rate through time from SEIJR trajectory sample and reported cases
#' 
#'
#' @param trajdf Either a dataframe or a path to rds containing a data frame with a posterior sample of trajectories (see combine_traj)
#' @param case_data dataframe containing reported/confirmed cases to be plotted alongside estimates. *Must* contain columns 'Date' and 'Confirmed'. Ensure Date is not a factor or character (see as.Date )
#' @param date_limits  a 2-vector containing bounds for the plotting window. If the upper bound is missing, will use the maximum time in the trajectories
#' @param path_to_save Will save a png here 
#' @return a list with derived outputs from the trajectories. The first element is a ggplot object if you want to further customize the figure 
GMRF_SEIJR_plot_reporting <- SEIJR_plot_reporting
