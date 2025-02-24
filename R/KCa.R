get.KCa.ratio <- function(tt,st,exterr=TRUE){
    get.PD.ratio(tt,st,'K40',exterr,bratio=0.895)
}

get.KCa.age <- function(K40Ca40,sK40Ca40,exterr=TRUE){
    get.PD.age(K40Ca40,sK40Ca40,'K40',exterr=exterr,bratio=0.895)
}

KCa.age <- function(x,exterr=TRUE,i=NA,i2i=TRUE,
                    omit4c=NULL,projerr=FALSE){
    PD.age(x,'K40',exterr=exterr,i=i,i2i=i2i,
           bratio=0.895,omit4c=omit4c,projerr=projerr)
}
