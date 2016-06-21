---
title: "Machine Learning: what can it do for you?"
intro: "Did you ever question what it can do for you? This is a brief introduction to Machine Learning."
---

What is Machine Learning (ML)? It is training the computer to make it predict a value or recognize objects, speech, letters, music notes, etc. This is supervised learning, because the output label is defined.

Alternatively you can also find a set of clusters for example. This could be useful for finding market segments. This is called unsupervised learning, because the output label is not defined.

Training is done by using historical data. Data (called features in ML) can be multi-dimensional: for example to predict a house price based on it's size, number of bedrooms, facilities, etc.

But also a matrix of pixels can be used for instance. When we correctly trained our model we can use output matrix parameter (called theta)
to apply on the input parameters to recognize a digit in a image for example.

## Supervised Machine Learning

### Predicting a value
Based on some input parameters you could predict a value. For example this could be house price as said before. The input could be a it's size, number of bedrooms, etc. It could also be used to predict a trend. For example if a company's sales have increased steadily every month for the past few years, it would produce a line that that depicts the upward trend in sales. After creating the trend line, the company could use the slope of the line to forecast sales in future months.

![Using linear regression we could predict a value](/img/ml/linear_regression.gif)

Remember that a prediction may be not true in the end, but it gives a good _indication_ (if the model is correct) of what to expect. According to that you could take action, which might be a valuable thing to do.

### Classification
Classifying input data to a certain label is a powerful tool and has many applications.

One of the most famous examples of classification machine learning is spam detection. Based on input data (the email body, the sender, etc) the classification algorithm could detect whether a email is spam or not.

![A plotted Support Vector Machine (SVM) with a non-linear Gaussian Kernel. Implementing a binary classification algorithm (green/red)](/img/ml/svm_guassian_kernel.png)

Another example is detecting a car's license plate and after that scan it's letters. This might be useful when you are developing a traffic enforcement system saving the whole traffic enforcement organization a lot time (you would remove the need of having manually enter the license plate number).

There are many other applications like: detecting music notes, classifying music, speech recognition, object recognition and much more.

## Unsupervised Machine Learning

### Clustering
In some cases you would like to plot segments/clusters out of data. This could be useful to find out what kind of segments your market has or to reduce the number of colors in a image. You can as well find out how segments in social networks are grouped.

![A K-means clustering algorithm plotted](/img/ml/kmeans_diagram.gif)

Also a clustering algorithm is the backbone behind the search engines. Search engines try to group similar objects in one cluster and the dissimilar objects far from each other. It provides result for the searched data according to the nearest similar object which are clustered around the data to be searched.

### Anomaly detection

A anomaly is something that deviates from what is standard, normal, or expected. What could that be in your business?
In financial systems this may be fraud and in manufacturing systems this may be a defect. In software this could be a
suspicious behavior in the system for example

![A plotted graph with some anomalies](/img/ml/anomaly_detection.png)

Raising a flag or taking automated actions could be considered by if you implemented a anomaly detection algorithm successfully. Could this be useful for you?

## Some showcases
Over the past period I've seen some interesting Machine Learning applications. Some of them:

- [Automatic Colorization of Grayscale Images](https://github.com/satoshiiizuka/siggraph2016_colorization)
- [Automating Tinder with Eigenfaces](http://crockpotveggies.com/2015/02/09/automating-tinder-with-eigenfaces.html)
- [Improving Nudity Detection and NSFW Image Recognition](http://blog.algorithmia.com/2016/06/improving-nudity-detection-nsfw-image-recognition/)
- [Music Transcription with Convolutional Neural Networks](https://www.lunaverus.com/cnn)

## Conclusion
As you can see Machine Learning is a interesting field. Have you thought what it can do it for you? Mark de Jong (at Vectos) recently completed a course on Machine Learning at Coursera. If you have some ideas, let's have a coffee!
