### EXTREMAL COEFFICIENT BETWEEN ################
# {Y_s , Y_{s+h}}                               #
#################################################
require(SpatialExtremes)
require(ncdf4)
infile <- "../../../inputs/ww3/megagol2015a-gol.nc"
# siteInfoFile <- "../../../inputs/sitesInfo/sites-info.dat" #N-SvsW-E
siteInfoFile <- "../../../inputs/sitesInfo/sites-info-NEvsSE.dat"
# sites.xyz <- "../../../inputs/sitesInfo/sites.xyz.dat"
sites.xyz <- "../../../inputs/sitesInfo/CopyOfsites.xyz.dat"

# read sites geometry Info file and return a dataframe
getSiteGeomInfo <- function (file) {
  data.in <- read.csv2(file = file, header = TRUE, sep="\t",stringsAsFactors = FALSE)
  data.out <- data.in[,c(1,6,11,13)]
  data.out$dist.h <- as.numeric(data.out$dist.h)
  return (data.out)
}

# read sites xyz file
getSitesXYZ <- function (file) {
  return (read.csv2(file = file, header = FALSE))
}

# read data sequentially for a vector of node
extractData <- function (file,sites,year,var) {
  in.nc <- nc_open(filename = file, readunlim = FALSE) 
  
  y <- year-1960
  start <- floor((y-1)*24*365.25)+1
  end <- floor(y*24*365.25)+1
  
  res <- data.frame("obs"=seq(1,end-start))
  nb<-0
  for (site in sites) {
    data.var <- ncvar_get(nc = in.nc, varid = var ,start = c(site,start),count=c(1,end-start))
    res <- cbind(res,data.frame(site=data.var))
    nb<-nb+1
#     print(paste0("Read ",nb,"/",length(sites)," sites"))
  }
  nc_close(in.nc)
  colnames(res)<-c("obs",sites)
  return (res)
}

# convert data to frechet distrib. from empirical distrib.
toFrech <- function (df,sites) {
  require(SpatialExtremes)
  df.frech<-df
  for (site in sites) {
    df.frech[,(names(df.frech) %in% site)] <- gev2frech(df[,(names(df) %in% site)],emp = TRUE)
  } 
  return (df.frech)
}

# estim extremal coefficient between two vectors
theta.estimator.censored <- function (df.frech, df.siteGeomInfo, quantile, timegap, year) {
  
  df <- NULL
  
  for (i in 1:nrow(df.siteGeomInfo)) {
    dist.h <- df.siteGeomInfo$dist.h[i]
    orientation <- df.siteGeomInfo$label[i]
    s1 <- df.siteGeomInfo$S1[i]
    s2 <- df.siteGeomInfo$S2[i]
    
    Y.s1 <- df.frech[ , (names(df.frech) %in% s1)]
    Y.s2 <- df.frech[ , (names(df.frech) %in% s2)]
    
    if (is.na(Y.s1[1]) || is.na(Y.s2[1]))  {
      next; # chunt comput. when one of two is NA
    } else {
      U.s1 <- as.numeric(quantile(Y.s1,quantile))
      U.s2 <- as.numeric(quantile(Y.s2,quantile))
      
      s<-0
      m<-0
      indexMax<-(length(Y.s1))
      jseq<-seq(1,indexMax,by = timegap)
      
      U <- max(U.s1,U.s2)
      for (j in jseq) {
        max.couple <- max(Y.s1[j], Y.s2[j])
        
        if (max.couple > U) {
          m <- m + 1
        }
        s <- s + ( 1/max( max.couple, U ) )  
      }
      theta <- m / s
      df <- rbind(df,data.frame("distance"=dist.h,"orientation"=orientation,"theta"=theta,"year"=year))
    }
  }
  return (df)
}

# Function to plot theta distancelag
plotThetaDistanceLag <- function (df.res,omnidir) {
  require(ggplot2)
  require(reshape2)
  require(Hmisc)
  require(msir)
  
  p <- ggplot(data = df.res, mapping = aes(x=distance/1000,y=theta)) +
    theme(panel.background = element_rect(fill="white")) +
    theme_bw() +
    theme(text = element_text(size=20)) +
    theme(legend.position = c(0.85, 0.3)) + # c(0,0) bottom left, c(1,1) top-right.
    theme(legend.background = element_rect(fill = "#ffffffaa", colour = NA)) +
#     ggtitle(paste0("Extremal Coefficient distance - 500 bins")) +
    ylab(expression("Extremal Coefficient":hat(theta)(h))) + 
    xlab("Distance h (km)") +
#     scale_y_continuous(breaks=seq(1,2,by=0.25),minor_breaks=seq(1,2,by=0.125),limits=c(1,2))
  scale_y_continuous(breaks=seq(1,2,by=0.25),minor_breaks=seq(1,2,by=0.125))
  
  if (omnidir) {
    fit <- loess.sd(y = df.res$theta,x=df.res$distance/1000, nsigma = 1.96)
    df.prediction<-data.frame(distance=fit$x)
    df.prediction$fit<-fit$y
    df.prediction$upper <- fit$upper
    df.prediction$lower <- fit$lower
    df.prediction$theta <- fit$y
    
    p <- p + geom_point(alpha=0.7,shape=3) +
      geom_line(data=df.prediction, mapping=aes(x=distance,y=fit),alpha=1,size=1,colour="black") +
      geom_ribbon(data=df.prediction, aes(x=distance, ymax=upper, ymin=lower), fill="lightgrey", alpha=.15) +
      geom_line(data=df.prediction,aes(x=distance,y = upper), colour = 'grey') +
      geom_line(data=df.prediction,aes(x=distance,y = lower), colour = 'grey')
    
  } else {
    colours <- c("pink","lightblue")
    k<-1
    for (dir in unique(df.res$orientation)) {
      df.res.dir <- df.res[df.res$orientation %in% dir, ]
      fit <- loess.sd(y = df.res.dir$theta,x=df.res.dir$distance/1000, nsigma = 1.96)
      df.prediction<-data.frame(distance=fit$x)
      df.prediction$fit<-fit$y
      df.prediction$upper <- fit$upper
      df.prediction$lower <- fit$lower
      df.prediction$theta <- fit$y
      
      p <- p + geom_point(alpha=0.7,shape=3,aes(colour=orientation)) +
        geom_line(data=df.prediction, mapping=aes(x=distance,y=fit),alpha=1,size=1,colour=colours[k]) +
        geom_ribbon(data=df.prediction, aes(x=distance, ymax=upper, ymin=lower), fill=colours[k], alpha=.15) +
        geom_line(data=df.prediction,aes(x=distance,y = upper), colour = colours[k]) +
        geom_line(data=df.prediction,aes(x=distance,y = lower), colour = colours[k])
      k<-k+1
    }
  }
  
  print(p)
}


#################################################
#MAIN
#################################################

# Collect data
# years <- seq(2011,2012) 
years <- seq(1961,2012) 
# years <- c(2010)
res.total <- NULL
count<-0
achiv<-0
LOADDATA=FALSE
if (LOADDATA) {
  for (year in years) {
    print(paste0("Achievement: ",achiv,"/",length(years),"  ",Sys.time()))
    count<-count+1
    isCollected <- FALSE
    if (!isCollected) {
      data.siteGeomInfo <- getSiteGeomInfo(file = siteInfoFile)
      sites <- getSitesXYZ(file = sites.xyz)$V1
      data.var <- extractData(file = infile, sites = sites, year = year, var = "hs")
      drop<-c("obs")
      data.var <- data.var[,!(names(data.var) %in% drop )]
    }
    
    isTransformed <- FALSE
    if (!isTransformed) {
      data.var.frech <- toFrech(data.var,sites)  
    }
    
    isThetaEstimated <- FALSE
    if (!isThetaEstimated) {
      quantile <- 0.95
      timegap <- 1
      res <- theta.estimator.censored(data.var.frech,data.siteGeomInfo,quantile,timegap,year)
      #     levels(res$orientation)<-c("N-S","NE-SW","NW-SE","W-E")
          levels(res$orientation)<-c("NE-SW","SE-NW")
#       levels(res$orientation)<-c("N-S","W-E")
    }
    res.total <- rbind(res.total,res)
    achiv<-achiv+1
  }  
  res<-res.total
  rm(res.total)
}

# plotThetaDistanceLag(res[1<res$theta & res$theta < 2.04 ,])

omniDir<-FALSE
n.bins <- 1500
dist <- res$distance
angles <- as.numeric(factor(levels(res$orientation)))
res.bin <- NULL
if (!is.null(n.bins)) {
  bins <- c(0, quantile(dist, 1:n.bins/(n.bins + 1)), max(dist))
  if (omniDir) {
    thetaBinned <- matrix(NA, nrow = n.bins + 1, ncol = 1)
      for (k in 1:(n.bins + 1)) {
        idx <- which((dist <= bins[k + 1]) & (dist > bins[k]) )
        if (length(idx) > 0) 
          thetaBinned[k,1] <- median(res$theta[idx])
    }
  } else {
    thetaBinned <- matrix(NA, nrow = n.bins + 1, ncol = length(angles))
    orientation <- res$orientation 
    for (a in angles) {
      for (k in 1:(n.bins + 1)) {
        idx <- which((dist <= bins[k + 1]) & (dist > bins[k]) & (as.numeric(orientation) == a) )
        if (length(idx) > 0) 
          thetaBinned[k,a] <- median(res$theta[idx])
      } 
    }
  }
  
  dist.bins <- (bins[-1] + bins[-(n.bins + 2)])/2
  
  if (omniDir) {
    res.bin<-rbind(res.bin,data.frame("theta"=thetaBinned[,1],"distance"=dist.bins))
  } else {
    for (a in angles) {
      res.bin<-rbind(res.bin,data.frame("theta"=thetaBinned[,a],"distance"=dist.bins,"orientation"=levels(res$orientation)[a]))
    } 
  }
} else {
  if (omniDir) {
    res.bin<-data.frame("theta"=res$theta,"distance"=res$distance)
  } else {
    res.bin<-data.frame("theta"=res$theta,"distance"=res$distance,"orientation"=res$orientation)
  }
}
# res.bin<-data.frame("theta"=thetaBinned,"distance"=dist.bins)
# plotThetaDistanceLag(res.bin[1<res.bin$theta & res.bin$theta < 2.04 & !is.na(res.bin$theta) ,])
plotThetaDistanceLag(res.bin[ !is.na(res.bin$theta) ,],omniDir)
