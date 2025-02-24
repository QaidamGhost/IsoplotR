# returns the lower and upper intercept age (for Wetherill concordia)
# or the lower intercept age and 207Pb/206Pb intercept (for Tera-Wasserburg)
concordia.intersection.ludwig <- function(x,wetherill=TRUE,exterr=FALSE,
                                          oerr=3,model=1,anchor=0){
    fit <- ludwig(x,exterr=exterr,model=model,anchor=anchor)
    out <- fit
    out$format <- x$format
    if (wetherill & !measured.disequilibrium(x$d)){
        wfit <- twfit2wfit(fit,x)
        out$par <- wfit$par
        out$cov <- wfit$cov
    } else {
        out$par <- fit$par
        out$cov <- fit$cov
    }
    np <- length(out$par)
    if (inflate(out)){
        out$err <- matrix(NA,2,np)
        rownames(out$err) <- c('s','disp')
        out$err['disp',] <- sqrt(fit$mswd*diag(out$cov))
    } else {
        out$err <- matrix(NA,1,np)
        rownames(out$err) <- 's'
    }
    colnames(out$err) <- names(out$par)
    out$err['s',] <- sqrt(diag(out$cov))
    out
}
# extracts concordia intersection parameters from an ordinary York fit
concordia.intersection.ab <- function(a,b,covmat=matrix(0,2,2),
                                      exterr=FALSE,wetherill=FALSE,d=diseq()){
    l8 <- lambda('U238')[1]
    ta <- get.Pb207Pb206.age(a,d=d)[1]
    out <- c(1,a) # tl, 7/6 intercept
    if (wetherill) names(out) <- c('t[l]','t[u]')
    else names(out) <- c('t[l]','a0')
    if (b<0) { # negative slope => two (or zero) intersections with concordia line
        tb <- get.Pb206U238.age(-b/a,d=d)[1]
        tlu <- recursive.search(tm=tb,tM=ta,a=a,b=b,d=d)
        out['t[l]'] <- tlu[1]
        if (wetherill) out['t[u]'] <- tlu[2]
    } else {
        search.range <- c(ta,2/l8)
        out['t[l]'] <- stats::uniroot(intersection.misfit.york,
                                      interval=search.range,a=a,b=b,d=d)$root
    }
    out
}

recursive.search <- function(tm,tM,a,b,d=diseq(),depth=1){
    out <- c(NA,NA)
    if (depth<3){
        mid <- (tm+tM)/2
        mfmin <- intersection.misfit.york(tm,a=a,b=b,d=d)
        mfmid <- intersection.misfit.york(mid,a=a,b=b,d=d)
        mfmax <- intersection.misfit.york(tM,a=a,b=b,d=d)
        if (mfmin*mfmid<0){ # different signs
            out[1] <- stats::uniroot(intersection.misfit.york,
                                     interval=c(tm,mid),a=a,b=b,d=d)$root
        } else {
            out <- recursive.search(tm=tm,tM=mid,a=a,b=b,d=d,depth=depth+1)
        }
        if (mfmax*mfmid<0){ # different signs
            out[2] <- stats::uniroot(intersection.misfit.york,
                                     interval=c(mid,tM),a=a,b=b,d=d)$root
        } else {
            tlu <- recursive.search(tm=mid,tM=tM,a=a,b=b,d=d,depth=depth+1)
            if (is.na(out[1])) out[1] <- tlu[1]
            if (is.na(out[2])) out[2] <- tlu[2]
        }
        if (all(is.na(out))){ # no intersection
            tlu <- stats::optimise(intersection.misfit.york,
                                   interval=c(tm,tM),a=a,b=b,d=d)$minimum
            out <- rep(tlu,2)
        }
    }
    out
}

# extract the lower and upper discordia intercept from the parameters
# of a Ludwig fit (initial Pb ratio and lower intercept age)
twfit2wfit <- function(fit,x){
    tt <- fit$par['t']
    buffer <- 1 # start searching 1Ma above or below first intercept age
    l5 <- lambda('U235')[1]
    l8 <- lambda('U238')[1]
    U <- iratio('U238U235')[1]
    if (fit$model==3){
        E <- matrix(0,4,4)
        J <- matrix(0,3,4)
        w <- fit$par['w']
    } else {
        E <- matrix(0,3,3)
        J <- matrix(0,2,3)
    }
    if (x$format %in% c(1,2,3)){
        a0 <- 1
        b0 <- fit$par['a0']
        E[-2,-2] <- fit$cov
    } else {
        a0 <- fit$par['a0']
        b0 <- fit$par['b0']
        E <- fit$cov
    }
    md <- mediand(x$d)
    D <- mclean(tt,d=md)
    disc.slope <- a0/(b0*U)
    conc.slope <- D$dPb206U238dt/D$dPb207U235dt
    if (disc.slope < conc.slope){
        search.range <- c(tt,get.Pb207Pb206.age(b0/a0,d=md)[1])+buffer
        tl <- tt
        tu <- stats::uniroot(intersection.misfit.ludwig,interval=search.range,
                             t2=tt,a0=a0,b0=b0,d=md)$root
    } else {
        search.range <- c(0,tt-buffer)
        if (check.equilibrium(d=md)) search.range[1] <- -1000
        tl <- tryCatch(
            stats::uniroot(intersection.misfit.ludwig,
                           interval=search.range,
                           t2=tt,a0=a0,b0=b0,d=md)$root
          , error=function(e){
              stop("Can't find the lower intercept.",
                   "Try fitting the data in Tera-Wasserburg space.")
          })
        tu <- tt
    }
    du <- mclean(tt=tu,d=md)
    dl <- mclean(tt=tl,d=md)
    XX <- du$Pb207U235 - dl$Pb207U235
    YY <- du$Pb206U238 - dl$Pb206U238
    BB <- a0/(b0*U)
    D <- (YY-BB*XX)^2 # misfit
    dXX.dtu <-  du$dPb207U235dt
    dXX.dtl <- -dl$dPb207U235dt
    dYY.dtu <-  du$dPb206U238dt
    dYY.dtl <- -dl$dPb206U238dt
    dBB.da0 <-  1/(b0*U)
    dBB.db0 <- -BB/b0
    dD.dtl <- 2*(YY-BB*XX)*(dYY.dtl-BB*dXX.dtl)
    dD.dtu <- 2*(YY-BB*XX)*(dYY.dtu-BB*dXX.dtu)
    dD.da0 <- 2*(YY-BB*XX)*(-dBB.da0*XX)
    dD.db0 <- 2*(YY-BB*XX)*(-dBB.db0*XX)
    if (conc.slope > disc.slope){
        J[1,1] <- 1
        J[2,1] <- -dD.dtl/dD.dtu
        J[2,2] <- -dD.da0/dD.dtu
        J[2,3] <- -dD.db0/dD.dtu
    } else {
        J[1,1] <- -dD.dtu/dD.dtl
        J[1,2] <- -dD.da0/dD.dtl
        J[1,3] <- -dD.db0/dD.dtl
        J[2,1] <- 1
    }
    out <- list()
    if (fit$model==3){
        out$par <- c(tl,tu,w)
        J[3,4] <- 1
        nms <- c('t[l]','t[u]','w')
    } else {
        out$par <- c(tl,tu)
        nms <- c('t[l]','t[u]')
    }
    out$cov <- J %*% E %*% t(J)
    rownames(out$cov) <- colnames(out$cov) <- names(out$par) <- nms
    out
}

# t1 = 1st Wetherill intercept, t2 = 2nd Wetherill intercept
# a0 = 64i, b0 = 74i on TW concordia
intersection.misfit.ludwig <- function(t1,t2,a0,b0,d=diseq()){
    tl <- min(t1,t2)
    tu <- max(t1,t2)
    l5 <- lambda('U235')[1]
    l8 <- lambda('U238')[1]
    U <- iratio('U238U235')[1]
    du <- mclean(tt=tu,d=d)
    dl <- mclean(tt=tl,d=d)
    XX <- du$Pb207U235 - dl$Pb207U235
    YY <- du$Pb206U238 - dl$Pb206U238
    BB <- a0/(b0*U)
    # misfit is based on difference in slope in Wetherill space
    YY - BB*XX
}
# a = intercept, b = slope on TW concordia
intersection.misfit.york <- function(tt,a,b,d=diseq()){
    D <- mclean(tt=tt,d=d)
    # misfit is based on difference in slope in TW space
    #D$Pb207U235/U - a*D$Pb206U238 - b
    (D$Pb207Pb206-a)*D$Pb206U238 - b
}

discordia.line <- function(fit,wetherill,d=diseq(),oerr=3){
    X <- c(0,0)
    Y <- c(0,0)
    l5 <- lambda('U235')[1]
    l8 <- lambda('U238')[1]
    J <- matrix(0,1,2)
    usr <- graphics::par('usr')
    if (wetherill){
        if (measured.disequilibrium(d)){
            U85 <- iratio('U238U235')[1]
            fit2d <- tw3d2d(fit)
            xy1 <- age_to_wetherill_ratios(fit$par[1],d=d)
            x1 <- xy1$x[1]
            x2 <- usr[2]
            y1 <- xy1$x[2]
            dydx <- 1/(U85*fit$par[2])
            y2 <- y1 + (x2-x1)*dydx
            X <- c(x1,x2)
            Y <- c(y1,y2)
            cix <- NA # computing confidence envelopes is very tricky
            ciy <- NA # for this rarely used function -> don't bother
        } else {
            tl <- fit$par[1]
            tu <- fit$par[2]
            X <- age_to_Pb207U235_ratio(c(tl,tu),d=d)[,'75']
            Y <- age_to_Pb206U238_ratio(c(tl,tu),d=d)[,'68']
            x <- seq(from=max(0,usr[1],X[1]),to=min(usr[2],X[2]),length.out=50)
            du <- mclean(tt=tu,d=d)
            dl <- mclean(tt=tl,d=d)
            aa <- du$Pb206U238 - dl$Pb206U238
            bb <- x - dl$Pb207U235
            cc <- du$Pb207U235 - dl$Pb207U235
            dd <- dl$Pb206U238
            y <- aa*bb/cc + dd
            dadtl <- -dl$dPb206U238dt
            dbdtl <- -dl$dPb207U235dt
            dcdtl <- -dl$dPb207U235dt
            dddtl <- dl$dPb206U238dt
            dadtu <- du$dPb206U238dt
            dbdtu <- 0
            dcdtu <- du$dPb207U235dt
            dddtu <- 0
            J1 <- dadtl*bb/cc + dbdtl*aa/cc - dcdtl*aa*bb/cc^2 + dddtl # dydtl
            J2 <- dadtu*bb/cc + dbdtu*aa/cc - dcdtu*aa*bb/cc^2 + dddtu # dydtu
            E11 <- fit$cov[1,1]
            E12 <- fit$cov[1,2]
            E22 <- fit$cov[2,2]
            sy <- errorprop1x2(J1,J2,fit$cov[1,1],fit$cov[2,2],fit$cov[1,2])
            ciy <- ci(x=y,sx=sy,oerr=oerr,absolute=TRUE)
            ul <- y + ciy
            ll <- y - ciy
            t75 <- get.Pb207U235.age(x,d=d)[,'t75']
            yconc <- age_to_Pb206U238_ratio(t75,d=d)[,'68']
            overshot <- ul>yconc
            ul[overshot] <- yconc[overshot]
            cix <- c(x,rev(x))
            ciy <- c(ll,rev(ul))
        }
    } else {
        fit2d <- tw3d2d(fit)
        X[1] <- age_to_U238Pb206_ratio(fit2d$par['t'],d=d)[,'86']
        Y[1] <- age_to_Pb207Pb206_ratio(fit2d$par['t'],d=d)[,'76']
        r75 <- age_to_Pb207U235_ratio(fit2d$par['t'],d=d)[,'75']
        r68 <- 1/X[1]
        Y[2] <- fit2d$par['a0']
        xl <- X[1]
        yl <- Y[1]
        y0 <- Y[2]
        tl <- check.zero.UPb(fit2d$par['t'])
        U <- settings('iratio','U238U235')[1]
        nsteps <- 100
        x <- seq(from=max(.Machine$double.xmin,usr[1]),to=usr[2],length.out=nsteps)
        y <- yl + (y0-yl)*(1-x*r68) # = y0 + yl*x*r68 - y0*x*r68
        D <- mclean(tt=tl,d=d)
        d75dtl <- D$dPb207U235dt
        d68dtl <- D$dPb206U238dt
        dyldtl <- (d75dtl*r68 - r75*d68dtl)/(U*r68^2)
        J1 <- dyldtl*x*r68 + yl*x*d68dtl - y0*x*d68dtl # dy/dtl
        J2 <- 1 - x*r68                                # dy/dy0
        sy <- errorprop1x2(J1,J2,fit2d$cov[1,1],fit2d$cov[2,2],fit2d$cov[1,2])
        ciy <- ci(x=y,sx=sy,oerr=oerr,absolute=TRUE)
        ul <- y + ciy
        ll <- y - ciy
        yconc <- rep(0,nsteps)
        t68 <- get.Pb206U238.age(1/x,d=d)[,'t68']
        yconc <- age_to_Pb207Pb206_ratio(t68,d=d)[,'76']
        # correct overshot confidence intervals:
        if (y0>yl){ # negative slope
            overshot <- (ll<yconc & ll<y0/2)
            ll[overshot] <- yconc[overshot]
            overshot <- (ul<yconc & ul<y0/2)
            ul[overshot] <- yconc[overshot]
        } else {    # positive slope
            overshot <- ul>yconc
            ul[overshot] <- yconc[overshot]
            overshot <- ll>yconc
            ll[overshot] <- yconc[overshot]
        }
        cix <- c(x,rev(x))
        ciy <- c(ll,rev(ul))
    }
    graphics::polygon(cix,ciy,col='gray80',border=NA)
    graphics::lines(X,Y)
}

tw3d2d <- function(fit){
    out <- list(par=fit$par,cov=fit$cov)
    if (fit$format > 3){
        labels <- c('t','a0')
        out$par <- c(fit$par['t'],fit$par[3]/fit$par[2]) # par = c(Pb206i,Pb207i)
        J <- matrix(0,2,3)
        J[1,1] <- 1
        J[2,2] <- -fit$par[3]/fit$par[2]^2
        J[2,3] <- 1/fit$par[2]
        out$cov <- J %*% fit$cov[1:3,1:3] %*% t(J)
        names(out$par) <- labels
        colnames(out$cov) <- labels
    }
    out
}

# this would be much easier in unicode but that doesn't render in PDF:
discordia.title <- function(fit,wetherill,sigdig=2,oerr=1,...){
    line1 <- maintit(x=fit$par[1],sx=fit$err[,1],n=fit$n,df=fit$df,
                     sigdig=sigdig,oerr=oerr,prefix='lower intercept =')
    if (wetherill){
        line2 <- maintit(x=fit$par[2],sx=fit$err[,2],ntit='',df=fit$df,
                         sigdig=sigdig,oerr=oerr,prefix='upper intercept =')
    } else if (fit$format<4){
        line2 <- maintit(x=fit$par['a0'],sx=fit$err[,'a0'],ntit='',
                         sigdig=sigdig,oerr=oerr,units='',df=fit$df,
                         prefix=quote('('^207*'Pb/'^206*'Pb)'[o]*'='))
    } else if (fit$format<7){
        line2 <- maintit(x=fit$par['a0'],sx=fit$err[,'a0'],ntit='',
                         sigdig=sigdig,oerr=oerr,units='',df=fit$df,
                         prefix=quote('('^206*'Pb/'^204*'Pb)'[o]*'='))
        line3 <- maintit(x=fit$par['b0'],sx=fit$err[,'b0'],ntit='',
                         sigdig=sigdig,oerr=oerr,units='',df=fit$df,
                         prefix=quote('('^207*'Pb/'^204*'Pb)'[o]*'='))
    } else if (fit$format<9){
        i86 <- 1/fit$par['a0']
        i87 <- 1/fit$par['b0']
        i86err <- i86*fit$err[,'a0']/fit$par['a0']
        i87err <- i87*fit$err[,'b0']/fit$par['b0']
        line2 <- maintit(x=i86,sx=i86err,ntit='',sigdig=sigdig,oerr=oerr,units='',
                         df=fit$df,prefix=quote('('^208*'Pb/'^206*'Pb)'[o]*'='))
        line3 <- maintit(x=i87,sx=i87err,ntit='',sigdig=sigdig,oerr=oerr,units='',
                         df=fit$df,prefix=quote('('^208*'Pb/'^207*'Pb)'[o]*'='))
    } else {
        stop('Invalid U-Pb data format.')
    }
    if (fit$model==1){
        line4 <- mswdtit(mswd=fit$mswd,p=fit$p.value,sigdig=sigdig)
    } else if (fit$model==3){
        line4 <- disptit(w=fit$par['w'],sw=sqrt(fit$cov['w','w']),
                         units=' Ma',sigdig=sigdig,oerr=oerr)
    }
    extrarow <- fit$format>3 & !wetherill
    if (fit$model==1 & extrarow){
        mymtext(line1,line=3,...)
        mymtext(line2,line=2,...)
        mymtext(line3,line=1,...)
        mymtext(line4,line=0,...)
    } else if (fit$model==2 & extrarow){
        mymtext(line1,line=2,...)
        mymtext(line2,line=1,...)
        mymtext(line3,line=0,...)
    } else if (fit$model==3 & extrarow){
        mymtext(line1,line=3,...)
        mymtext(line2,line=2,...)
        mymtext(line3,line=1,...)
        mymtext(line4,line=0,...)
    } else if (fit$model==1){
        mymtext(line1,line=2,...)
        mymtext(line2,line=1,...)
        mymtext(line4,line=0,...)
    } else if (fit$model==2){
        mymtext(line1,line=1,...)
        mymtext(line2,line=0,...)
    } else if (fit$model==3){
        mymtext(line1,line=2,...)
        mymtext(line2,line=1,...)
        mymtext(line4,line=0,...)
    }
}
