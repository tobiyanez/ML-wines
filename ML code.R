library(tree) #to fit trees
library(randomForest) #for random forests (and bagging)
library(gbm) #for boosting
library(ggplot2) #for any graphics we may create
library(ROCR) #for plots
library(boot) #for cv.glm function
library(MASS) #for lda function
library(ipred) #for cv/bagging/etc. functions
library(car)
library(tidyverse) #for general data manipulation

data <- read.csv("wineQualityN.csv")

glimpse(data)
#chemical characteristics of wines + quality 

sum(is.na(data))
#data appears fairly clean only 38 NAs

data <- data %>% 
  mutate(type = case_when(type == "white" ~ 1,
                          type == "red" ~ 0,
                          TRUE ~ 999))
#since we have both red and white wines we want to convert it into a factor variable
unique(data$type) #no NAs

#seeing what pairs look to be generally correlated
pairs(data[,2:13], lower.panel = NULL, main="Scatterplot of Quantitative Variables")
round(cor(data[,2:13]),3)

#look to be high correlations between alcohol, density and sugar , makes sense as alcohol is less dense than water,
#thus adding more would decrease density, also high correlation between total sulfer dioxide and free sulfer
#and funnily enough correlation between alcohol content and quality (and volatile acidity)

#density, sugar, and alcohol all correlated
#makes sense chemically


#establishing quality variable to measure if wine is above or below median quality
#in order to classify good vs bad wine
test <- function(x) {
  ifelse(
    x<median(data$quality),
    0,
    1
  )}
data$quality_cat <- factor(test(data$quality))
View(data)

#volatile acidity + alcohol seem to be related to quality
ggplot(data = data) + 
  geom_boxplot(mapping = aes(x = quality_cat, y = volatile.acidity)) + theme_classic()

ggplot(data = data) + 
  geom_boxplot(mapping = aes(x = quality_cat, y = alcohol)) + theme_classic()



#setting RNG to match newer R versions
#creating a training data set and a testing data set to determine
#how well the model works
RNGkind(sample.kind = "Rejection") #in order to match newer R RNG
                                   #New R uses rejection not rounding
set.seed(1)

#spliting data into testing and training data
#50-50 split as to not overtrain
sample.data<-sample.int(nrow(data), floor(.50*nrow(data)), replace = F)
train<-data[sample.data, ]
test<-data[-sample.data, ]

#################################################
## Regression ##
#################################################

#in this section we are trying to use chemical makeup and quality to predict alcohol content

#setting the response variable to be the alcohol content in the wine
test.y<-test[,"alcohol"]

#starting with simple linear regression with all variables except quality cat
model <- lm(alcohol~.-quality_cat, data=data)

# can see that almost all variables are statistically significant, hard to make decisions based off this
summary(model)


#building a simple classification tree 
#This is helpful because it's easy to make decisions based off of this
tree.reg.train<-tree(alcohol~.-quality_cat, data=train) # using all vars except quality_cat 
summary(tree.reg.train)
plot(tree.reg.train)
text(tree.reg.train, cex=0.75, pretty=0)
#density is the "most important" factor, makes up the first two splits

tree.pred.test<-predict(tree.reg.train, newdata=test) 
mean((tree.pred.test - test.y)^2) # test error rate

#used this model on the test data set
#the test error rate was ~.541 which is not great
#Lets see if we can improve it

#cross validation to improve model building + model selection by splitting up data 
#using K=10 fold cross validation to split data into ten sets and pruining
#in order to improve the regression
cv.reg<-cv.tree(tree.reg.train, K=10)
cv.reg

trees.num.class<-cv.reg$size[which.min(cv.reg$dev)]
trees.num.class

plot(cv.reg$size, cv.reg$dev, type='b')

prune.reg<-prune.tree(tree.reg.train, best=trees.num.class)
prune.reg
plot(prune.reg)
text(prune.reg, cex=0.75, pretty=0)

#prediction based on pruned tree for test data
tree.pred.prune<-predict(prune.reg, newdata=test)

#overall accuracy
mean((tree.pred.prune - test.y)^2) 

#pruning and cross validation did not impact 
#test error rate, not an uncommon occurance, test and train data are not very different

#################################################
## Bagging ##
#################################################

#bagging is special case of random forest when mtry = number of predictors
#used to reduce variance and increase accuracy through resampling
names(train)
bag.reg <- randomForest(alcohol~.-quality_cat, data=train, mtry=12, importance=TRUE)

#importance measures of predictors
importance(bag.reg)
#graphical version
varImpPlot(bag.reg)

#the biggest factors in alcohol concentration in wine are the 
#density and residual sugar content of the wine

pred.bag<-predict(bag.reg, newdata=test)
mean((pred.bag - test.y)^2)
# The error rate is down to .180. Much improved!

#################################################
## Random Forest ##
#################################################

# Since this is a regression tree p/3 is the sample of predictors each time, which is 4 in this case.
rf.reg<-randomForest(alcohol~.-quality_cat, data=train, mtry=4, importance=TRUE)

#importance measures of predictors
importance(rf.reg)
#graphical version
varImpPlot(rf.reg)

#density and residual sugar are again shown to be 
#the two most important variables when predicting alcohol
#content

#test accuracy with random forest
pred.rf<-predict(rf.reg, newdata=test)
mean((pred.rf - test.y)^2)
#The error rate is .212, much better than normal regression
#Not quite as low as bagging

#################################################
## Classification ##
#################################################

#in this section we try to predict the quality of the wine based on chemical characteristics 
#as good or bad

#this time predicting for the quality of the wine
#strating off again with a non machine learning regression
LogisticRegression <- glm(quality_cat ~ .-quality, data = train, family = "binomial")

par(mfrow=c(2,2))
plot(LogisticRegression)
#requisites of logistic regression look good


cooksd <- cooks.distance(LogisticRegression)
plot(cooksd, pch="*", cex=2, main="Influential Obs by Cooks distance")  # plot cook's distance
abline(h = 4*mean(cooksd, na.rm=T), col="red")  # add cutoff line
text(x=1:length(cooksd)+1, y=cooksd, labels=ifelse(cooksd>4*mean(cooksd, na.rm=T),names(cooksd),""), col="red")  # add labels
#cooks d looks fine

summary(LogisticRegression)
#volatile acidity, residual sugar, sulfer dioxide (free + total), sulphates and alcohol are significant

#looking at variance inflation
vif(LogisticRegression)

#density is well above 10 so we remove it, it's has a lot of covariance 
#(as we saw in the first correlation graphs)

data$density <- NULL

LogTest<-round(predict(LogisticRegression, newdata=test, type="response")) 
table(test.y, LogTest)
1 - mean(LogTest != test.y, na.rm = TRUE)
#generally a pretty good regression, ~73.8% accurate


#moving on to creating a regression tree based on quality
test.y <- test[,"quality_cat"]

tree.class.train<-tree(quality_cat~.-quality, data=train)
summary(tree.class.train)

plot(tree.class.train)
text(tree.class.train, cex=0.75, pretty=0,main="Figure 4.1.4")

tree.pred.test<-predict(tree.class.train, newdata=test, type="class") 
#confusion matrix for test data
table(test.y, tree.pred.test)
mean(tree.pred.test != test.y)
#test mse of .274
#correct ~73.1% of the time, still not bad, but worse than logistic regression, alcohol is the biggest factor

#using cross validation and pruning to attempt to improve the tree
cv.class<-cv.tree(tree.class.train, K=10, FUN = prune.misclass)
cv.class

trees.num.class<-cv.class$size[which.min(cv.class$dev)]
trees.num.class

plot(cv.class$size, cv.class$dev, type='b',main="Figure 4.2.1",ylab='Deviance',xlab="Size")

prune.class <-prune.tree(tree.class.train, best=3)
summary(prune.class)
plot(prune.class)
text(prune.class, cex=0.75, pretty=0)

#prediction based on pruned tree for test data
tree.pred.prune<-predict(prune.class, newdata=test, type="class")

#overall accuracy
mean(tree.pred.prune != test.y) 
# test mse of .274, again pruning/cv has no effect on our tree

#################################################
## Bagging ##
#################################################

names(train)
bag.class<-randomForest(quality_cat~.-quality, data=train, mtry=12, importance=TRUE)

#importance measures of predictors
importance(bag.class)
#graphical version
varImpPlot(bag.class)

#alcohol content is by far the biggest predictor in what 
#makes a wine classify as above average

#test accuracy with bagging
pred.bag<-predict(bag.class, newdata=test, type = "response")

# Confusion Matrix
table(test.y, pred.bag)
mean(pred.bag != test.y)
#mse down to .196, again much improved!
#correct over 80% of the time now!

plot(bag.class)
text(bag.class, cex=0.75, pretty=0)
#################################################
## Random Forest ##
#################################################

#Since this is a classification tree we will 
#use sqrt(p) as our sample of predictors each time, 
#which is 3 (3.46) in this case.
rf.class<-randomForest(quality_cat~.-quality, data=train, mtry=3, importance=TRUE)

#importance measures of predictors
importance(rf.class)
#graphical version
varImpPlot(rf.class)

#test accuracy with random forest
pred.rf<-predict(rf.class, newdata=test, type = "response")

# Confusion Matrix
table(test.y, pred.rf)
mean(pred.rf != test.y)
#.189 mse, marginally lower than bagging
plot(rf.class)
text(rf.class, cex=0.75, pretty=0)
