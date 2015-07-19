require(ncdf4)

# Fit GPD
margGPDfit <- function (data,quantile,r=1,cmax=FALSE) {
  require(evd)  
  #find parameters
  fit<-fpot(data,threshold=quantile,r=r,cmax=cmax)
  
  return(list(threshold=as.numeric(fit$threshold),
              scale=as.numeric(fit$estimate['scale']),
              shape=as.numeric(fit$estimate['shape']),
              std.err=fit$std.err))
}

# amin function to fit mu sigma xi
amin<-function(theta,x) {
  if ( (theta[2] < 1*10^(-4)) | (theta[3] == 0)) {
    return (9999999)
  } else {
    c <- theta[1]-theta[2]/theta[3]
    coef <- ( (1/theta[3]) + 1 )
    n <- length(x)
    val <- 0
    j<-0
    if (theta[3] > 0) {
      for (i in 1:n) {
        if (x[i] > c) {
          val <- val+log(1 + theta[3] * ((x[i]-theta[1])/theta[2]))
          j<-j+1
        }
      }
    } else if (theta[3] < 0) {
      for (i in 1:n) {
        if (x[i] < c ) {
          val <- val+log(1 + theta[3] * ((x[i]-theta[1])/theta[2]))
          j<-j+1
        }
      }
    }
    if (j == length(x)) {
      return (n * log(theta[2]) + coef*val)
    } else {
      return (9999999)
    }
  }
}

# nlmin amin
aminnlmin <- function (start,d) {
  res <- nlminb(start = start, objective = amin, x=d,
                hessian = F, lower=c(-Inf,1*10^(-4),-1),
                upper=c(min(d),Inf,1), control = list(iter.max=1000))
  if (res$convergence == 0) {
    return (c(res$par,res$objective))
  } else {
    return (c(NA,NA,NA,NA))
  }
}

# optim amin
aminoptim <- function (start,d) {
  res <- optim(par = start, fn = amin,x=d,hessian = F,
               lower=c(-Inf,1*10^(-4),-1),
               upper=c(min(d),Inf,1),control = list(maxit=1000),method="L-BFGS-B")
  if (res$convergence == 0) {
    return (c(res$par,res$value))
  } else {
    return (c(NA,NA,NA,NA))
  }
}

# maginal GEV fit over threshold exceedance 
marginGEVExceedanceFit <- function (x,quantile=0.95,cmax=TRUE,r=6) {
  threshold <- as.numeric(quantile(x,quantile))
  if (cmax) {
    exceed <- as.numeric(clusters(x, u = threshold, r = r, cmax = TRUE, keep.names = FALSE))
  } else {
    high <- (x > threshold) & !is.na(x)
    exceed <- as.double(x[high])
  }
  
  d <- exceed
  
  m <- matrix(0,5,3)
  m[,1] <- rep(1,5)
  m[,2] <- rep(3,5)
  m[,3] <- seq(-0.75,0.75,length=5)
  
  res.aminnlmin.mat <- apply(X = m, MARGIN = 1, FUN = aminnlmin, d=d)
  res.aminoptim.mat <- apply(X = m, MARGIN = 1, FUN = aminoptim, d=d)
  
  res.nlmin<-res.aminnlmin.mat[1:3,which.min(res.aminnlmin.mat[4,])]
  res.optim<-res.aminoptim.mat[1:3,which.min(res.aminoptim.mat[4,])]
  
  if (!is.na(res.nlmin[1])) {
    return (data.frame("loc"=res.nlmin[1],"scale"=res.nlmin[2],"shape"=res.nlmin[3],"threshold"=threshold))
  } else {
    return (data.frame("loc"=res.optim[1],"scale"=res.optim[2],"shape"=res.optim[3],"threshold"=threshold))
  }
}

# Fit GEV-over-threshold at any location of file and store both local threshold and scale parameters in a temp_file
# for re-use with NCBO (see NCO).
createMarginScaleParameters <- function (file,var,proba,r,cmax,tmpfitinfo.file,grid=TRUE) {
  source("extractTimeSerie.R")
  prec="single"
  missval=1.e30
  
  bs.nc.path <- tmpfitinfo.file
  
  in.nc <- nc_open(file,readunlim = FALSE)
  
  units.var <- ""
  units.time <- ""
  for (i in 1:in.nc$nvar) {
    v <- in.nc$var[[i]]
    if (v$name %in% var) {units.var <- v$units ;break}
  }
  for (i in 1:in.nc$ndim) {
    d <- in.nc$dim[[i]]
    if (d$name %in% "time") {units.time <- d$units ;break}
  }
  
  if (grid) { 
    ### TO DO : use V1.1.0 available at https://github.com/rc-34/SpaceTimeExtreme/releases ###
  } else {
    thres1D <- shape1D <- scale1D <- loc1D <- NULL
    
    node<-ncvar_get(in.nc,"node")
    time<-ncvar_get(in.nc,"time")
    
    if (env.parallel) {
      loc1D <- rep(-9999,length(node))
      scale1D <- rep(-9999,length(node))
      shape1D <- rep(-9999,length(node))
      thres1D <- rep(-9999,length(node))
      
      require(Rmpi)
      ## // function
      parallelfit <- function() {
        require(ncdf4)
        require(evd)
        # Tag for sent messages : 
        # 1 = ready_for_task ; 2 = done_task ; 3 = exiting
        # Tag for receive messages :
        # 1 = task ; 2 = done_tasks
        done <- 0
        junk <- 0
        while (done !=1) {
          master<-0 ; ready4task<-1
          #signal being ready to receive a new task
          mpi.send.Robj(junk,master,ready4task)
          #receive a task
          task <- mpi.recv.Robj(mpi.any.source(),mpi.any.tag())
          task_info <- mpi.get.sourcetag()
          tag <- task_info[2]
          bug=FALSE
          result<-NULL
          if (tag == 1) { #task to perform
            tryCatch({
              x<-as.numeric(unlist(task))
              varid<-var
              if (var=="tp") {varid<-"fp"}
              Xs.ref <- Xs(file,varid,index.location=c(x),grid=grid)
              if (var=="tp") { Xs.ref$var <- 1/Xs.ref$var }
              
              paramsXsGEV <- marginGEVExceedanceFit(x = na.omit(Xs.ref$var), quantile = 1-proba, cmax = cmax, r = r)
              result<-list(node=x,shape1D=paramsXsGEV$shape,scale1D=paramsXsGEV$scale,
                           thres1D=paramsXsGEV$threshold,loc1D=paramsXsGEV$loc)
            }, error = function(e) {print(paste("error:",e)); bug<-TRUE})
            if (bug) {
              result<-list(node=x)
              mpi.send.Robj(result,0,4) 
            } else {
              mpi.send.Robj(result,0,2)
            }
          } else if (tag==2) { #no more job to do
            done <-1
          }
        }
        #exiting
        mpi.send.Robj(junk,0,3)
      }
      
      ## Master part
      mpi.bcast.Robj2slave(parallelfit)
      mpi.bcast.Robj2slave(Xs)
      mpi.bcast.Robj2slave(marginGEVExceedanceFit)
      mpi.bcast.Robj2slave(amin)
      mpi.bcast.Robj2slave(aminnlmin)
      mpi.bcast.Robj2slave(aminoptim)
      mpi.bcast.Robj2slave(file)
      mpi.bcast.Robj2slave(var)
      mpi.bcast.Robj2slave(grid)
      mpi.bcast.Robj2slave(proba)
      mpi.bcast.Robj2slave(env.p)
      mpi.bcast.Robj2slave(r)
      mpi.bcast.Robj2slave(env.cmax)
      mpi.bcast.Robj2slave(env.consecutivebelow)
      print("data broadcasted")
      mpi.bcast.cmd(parallelfit())
      print("slaves launched")
      
      #create take list
      tasks <- vector('list')
      for (i in 1:length(node)) {  
        tasks[i] <- list(i=i)
      }
      closed_slaves<-0
      n_slaves<-mpi.comm.size()-1
      junk<-0
      while (closed_slaves < n_slaves) {
        #receive message from a slave
        message <- mpi.recv.Robj(mpi.any.source(),mpi.any.tag())
        message_info <- mpi.get.sourcetag()
        slave_id <- message_info[1]
        tag <- message_info[2]
        if (tag == 1) {
          #slave is ready for a task. Fetch next or send end-tag in case all tasks are computed.
          if (length(tasks) > 0) {
            #send a task and remove it from the list
            mpi.send.Robj(tasks[1],slave_id,1)
            tasks[1] <- NULL
          } else {
            #send signal that all tasks are already handled
            print("All tasks are handled. Signal to close down the slave...")
            mpi.send.Robj(junk, slave_id,2)
          }
        } else if (tag == 2) {
          #message contains results. Deal with it.
          res<-message
          shape1D[res$node]<-res$shape1D
          scale1D[res$node] <- res$scale1D
          loc1D[res$node] <- res$loc1D
          thres1D[res$node] <- res$thres1D
          print(paste("Margin GEV-over-Exceedances - Node:",res$node,"    THRES",res$thres1D,"MU",res$loc1D,"SIGMA",res$scale1D,"XI",res$shape1D))
        } else if (tag == 4) {
          res<-message
          warning(paste0("error during fitting at Node: ",res$node))
        } else if (tag == 3) {
          #a slave has closed down.
          closed_slaves <- closed_slaves + 1
        }
      }
    } else {
      for (x in 1:length(node)) {
        print(paste("Margin GEV-over-Exceedances - Node:",x))
        
        # TO DO BIVARIATE CASE #
        Xs.ref <- Xs(file,var,index.location=c(x),grid=grid)
        paramsXsGEV <- marginGEVExceedanceFit(x = Xs.ref$var, quantile = 1-proba, cmax = cmax, r = r)
        
        shape1D <- c(shape1D,paramsXsGEV$shape)
        scale1D <- c(scale1D,paramsXsGEV$scale)
        thres1D <- c(scale1D,paramsXsGEV$threshold)
        loc1D <- c(loc1D,paramsXsGEV$loc)
      }  
    }
    asreverse1D <- 1/scale1D
    
    dimNode <- ncdim_def("node", "count", node)
    dimTime <- ncdim_def("time", units.time, time,unlim=TRUE)
    
    varThres <- ncvar_def("u_s","",dimNode,missval=missval,prec="float",compression = 9)
    varShape <- ncvar_def("xi_s","",dimNode,missval=missval,prec="float",compression = 9)
    varScale <- ncvar_def("sigma_s","",dimNode,missval=missval,prec="float",compression = 9)
    varLoc_rep <- ncvar_def("mu_s_repeated",units.var,list(dimNode,dimTime),missval=missval,prec="float",compression = 9)
    varLoc <- ncvar_def("mu_s","",dimNode,missval=missval,prec="float",compression = 9)
    varInverseScale <- ncvar_def("inv_sigma_s_repeated","",list(dimNode,dimTime),missval=missval,prec="float",compression = 9)
    
    bs.nc <- nc_create(bs.nc.path,list(varThres,varLoc_rep,varLoc,varShape,varScale,varInverseScale))
    
    for (i in 1:length(time)) ncvar_put(bs.nc,varLoc_rep,loc1D,start=c(1,i),count=c(-1,1))
    ncvar_put(bs.nc,varLoc,loc1D,start=c(1),count=c(-1))
    ncvar_put(bs.nc,varThres,thres1D,start=c(1),count=c(-1))
    ncvar_put(bs.nc,varShape,shape1D,start=c(1),count=c(-1))
    ncvar_put(bs.nc,varScale,scale1D,start=c(1),count=c(-1))
    for (i in 1:length(time)) ncvar_put(bs.nc,varInverseScale,asreverse1D,start=c(1,i),count=c(-1,1))
  }
  # Close files
  nc_close(in.nc)
  nc_close(bs.nc)
}

# Returns a file with marginal values normalized from their local thresholds and scale paremeters from margin GPD fits
normalizeMargins <- function (file, var, tmpfitinfo.file, normalizedfile) {
  tmp.char <- paste(workdirtmp,"foo.nc",sep="/")
  
  tmp.inv.sigma.s<-paste(workdirtmp,"tmp_inv_sigma_s.nc",sep="/")
  system(command = paste(env,"ncks -4 -O -v inv_sigma_s_repeated",tmpfitinfo.file,tmp.inv.sigma.s))
  system(command = paste(env,"ncrename -O -v inv_sigma_s_repeated,",var," ",tmp.inv.sigma.s,sep=""))
  
  tmp.u.s<-paste(workdirtmp,"tmp_u_s.nc",sep="/")
  system(command = paste(env,"ncks -4 -O -v mu_s_repeated",tmpfitinfo.file,tmp.u.s))
  system(command = paste(env,"ncrename -O -v mu_s_repeated,",var," ",tmp.u.s,sep=""))
  
  system(command = paste(env,"ncbo -4 -O --op_typ=sbt",file,tmp.u.s,tmp.char))
  system(command = paste(env,"ncbo -4 -O --op_typ=mlt",tmp.char,tmp.inv.sigma.s,normalizedfile)) # multiply by the reverse 1/a(s)
  
  system(command = paste(env,"ncrename -O -v ",var,",",var,"_normalized ",normalizedfile,sep=""))
  system(command = paste(env,"ncks -A", normalizedfile, tmpfitinfo.file))
  system(command = paste(env,"rm", normalizedfile, tmp.char))
}