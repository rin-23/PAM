//
//  PAMUtilities.m
//  PAM
//
//  Created by Rinat Abdrashitov on 2013-11-27.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "PAMUtilities.h"
#import "Utilities.h"
#import "Quatd.h"
#import "ArithQuat.h"
#import "Manifold.h"

@implementation PAMUtilities

//+(std::vector<float>)ribWidthForSkeleton:(std::vector<GLKVector2>)skeleton
//                                 normals:(std::vector<GLKVector2>)normals
//                                tangents:(std::vector<GLKVector2>)tangents
//                             touchPoints:(std::vector<GLKVector2>)touchPoints
//{
//    //Get width
//    assert(skeleton.size() == normals.size());
//    
//    std::vector<float> skeletonWidth;
//
//    for (int sIndex = 0; sIndex < skeleton.size(); sIndex++)
//    {
//        GLKVector2 sPoint = skeleton[sIndex];
//        GLKVector2 norm;
//        GLKVector2 tangent = tangents[sIndex];
//        GLKVector2 normOpp = GLKVector2MultiplyScalar(norm, -1);
//        std::vector<GLKVector2> leftSkeletonIntersection;
//        std::vector<GLKVector2> rightSkeletonIntersection;
//
//        //Left norm
//        //intersect norm vector with every line segment
//        GLKVector2 tPoint = GLKVector2Subtract(touchPoints[0], sPoint);
//        int sign = ((tangent.x)*(tPoint.y) - (tangent.y)*(tPoint.x));
//        if (sign > 0) {
//            norm = GLKVector2MultiplyScalar(normals[sIndex], -1);
//        }
//        
//        for (int j = 0; j < touchPoints.size() - 2; j += 2)
//        {
//            //intersect norm vector with every line segment
//            GLKVector2 tPoint1 = GLKVector2Subtract(touchPoints[j], sPoint);
//            int sign1 = ((norm.x)*(tPoint1.y) - (norm.y)*(tPoint1.x));
//
//            GLKVector2 tPoint2 = GLKVector2Subtract(touchPoints[j+2], sPoint);
//            int sign2 = ((norm.x)*(tPoint2.y) - (norm.y)*(tPoint2.x));
//            
//            if (sign1 == 0) {
//                leftSkeletonIntersection.push_back(tPoint1);
//            } else if (sign2 ==0) {
//                leftSkeletonIntersection.push_back(tPoint2);
//            } else if (sign1 != sign2) {
//                leftSkeletonIntersection.push_back(GLKVector2Lerp(tPoint1, tPoint2, 0.5f));
//            }
//        }
//        
//        tPoint = GLKVector2Subtract(touchPoints[1], sPoint);
//        sign = ((tangent.x)*(tPoint.y) - (tangent.y)*(tPoint.x));
//        if (sign > 0) {
//            norm = GLKVector2MultiplyScalar(normals[sIndex], -1);
//        }
//
//        for (int j = 1; j < touchPoints.size() - 2; j += 2)
//        {
//            GLKVector2 tPoint1 = GLKVector2Subtract(touchPoints[j], sPoint);
//            int sign1 = ((norm.x)*(tPoint1.y) - (norm.y)*(tPoint1.x));
//            
//            GLKVector2 tPoint2 = GLKVector2Subtract(touchPoints[j+2], sPoint);
//            int sign2 = ((norm.x)*(tPoint2.y) - (norm.y)*(tPoint2.x));
//            
//            if (sign1 == 0) {
//                rightSkeletonIntersection.push_back(tPoint1);
//            } else if (sign2 ==0) {
//                rightSkeletonIntersection.push_back(tPoint2);
//            } else if (sign1 != sign2) {
//                rightSkeletonIntersection.push_back(GLKVector2Lerp(tPoint1, tPoint2, 0.5f));
//            }
//        }
//                
//        assert(leftSkeletonIntersection.size() > 0);
//        assert(rightSkeletonIntersection.size() > 0);
//        
//        GLKVector2 closestLeftPoint = leftSkeletonIntersection[0];
//        float closestLeftDist = GLKVector2Distance(closestLeftPoint, sPoint);
//        for (GLKVector2 closestCandidate: leftSkeletonIntersection) {
//            float curDist = GLKVector2Distance(closestCandidate, sPoint);
//            if (curDist < closestLeftDist) {
//                closestLeftDist = curDist;
//                closestLeftPoint = closestCandidate;
//            }
//        }
//        
//        GLKVector2 closestRightPoint = rightSkeletonIntersection[0];
//        float closestRightDist = GLKVector2Distance(closestRightPoint, sPoint);
//        for (GLKVector2 closestCandidate: rightSkeletonIntersection) {
//            float curDist = GLKVector2Distance(closestCandidate, sPoint);
//            if (curDist < closestRightDist) {
//                closestRightDist = curDist;
//                closestRightPoint = closestCandidate;
//            }
//        }
//        
//        float width = 0.5f*GLKVector2Distance(closestLeftPoint, closestRightPoint);
//        skeletonWidth.push_back(width);
//    }
//    
//    return skeletonWidth;
//}

+(void)normals:(std::vector<GLKVector2>&)normals 
      tangents:(std::vector<GLKVector2>&)tangents
   forSkeleton:(std::vector<GLKVector2>)skeleton
{
    //Get norm vectors
    for (int i = 0; i < skeleton.size(); i++) {
        if (i == 0) {
            continue;
        } else if (i == skeleton.size() - 1) {
            //add same norm and tangent for the last pole
            normals.push_back(normals[skeleton.size() - 2]);
            tangents.push_back(tangents[skeleton.size() - 2]);
        } else {
            GLKVector2 tangent = GLKVector2Subtract(skeleton[i+1], skeleton[i-1]); //i-1
            GLKVector2 firstHalf = GLKVector2Subtract(skeleton[i], skeleton[i-1]); //i-1
            GLKVector2 proj = [Utilities projectVector2:firstHalf ontoLine:tangent]; //i-1
            GLKVector2 norm = GLKVector2Normalize(GLKVector2Subtract(proj, firstHalf)); //i
            
            //make sure normals point in the same left direction
            float side = ((tangent.x)*(firstHalf.y) - (tangent.y)*(firstHalf.x));
            if (side == 0) {
                float theta = GLKMathDegreesToRadians(-90);
                float cs = cosf(theta), sn = sinf(theta);
                
                float px = firstHalf.x * cs - firstHalf.y * sn;
                float py = firstHalf.x * sn + firstHalf.y * cs;
                norm = GLKVector2Normalize(GLKVector2Make(px, py));

            } else if (!(side > 0)) {
                norm = GLKVector2MultiplyScalar(norm, -1);
            }
                        
            normals.push_back(norm);
            tangents.push_back(tangent);
            if (i == 1) {
                //add same norm and tangent for the first pole
                normals.insert(normals.begin(), normals[0]);
                tangents.insert(tangents.begin(), tangents[0]);
            }
        }
    }
}

+(void)normals3D:(std::vector<GLKVector3>&)normals
      tangents3D:(std::vector<GLKVector3>&)tangents
     forSkeleton:(std::vector<GLKVector3>)skeleton
{
    for (int i = 0; i < skeleton.size(); i++) {
        GLKVector3 t;
        if (i == 0) {
            t = GLKVector3Subtract(skeleton[1], skeleton[0]);
        } else if (i == (skeleton.size() - 1)) {
            t = GLKVector3Subtract(skeleton[i], skeleton[i-1]);
        } else {
            GLKVector3 v1 = GLKVector3Subtract(skeleton[i], skeleton[i-1]);
            GLKVector3 v2 = GLKVector3Subtract(skeleton[i+1], skeleton[i]);
            t = GLKVector3Lerp(v1, v2, 0.5f);
        }
        tangents.push_back(GLKVector3Normalize(t));
    }

    CGLA::Vec3d lastTangent = CGLA::Vec3d(tangents[0].x, tangents[0].y, tangents[0].z);
    GLKVector3 normGLK = [Utilities orthogonalVectorTo:tangents[0]];
    CGLA::Vec3d lastNorm = CGLA::Vec3d(normGLK.x, normGLK.y, normGLK.z);

    for (int i = 0; i < skeleton.size(); i++) {
        CGLA::Vec3d tangent = CGLA::Vec3d(tangents[i].x, tangents[i].y, tangents[i].z);
        CGLA::Quatd q;
        q.make_rot(lastTangent, tangent);
        CGLA::Vec3d curNorm = q.apply(lastNorm);
        GLKVector3 curNormGLK = GLKVector3Normalize(GLKVector3Make(curNorm[0], curNorm[1], curNorm[2]));
        normals.push_back(curNormGLK);
        lastTangent = tangent;
        lastNorm = curNorm;
    }
}

+(void)normals3D:(std::vector<GLKVector3>&)normals
      tangents3D:(std::vector<GLKVector3>&)tangents
     forSkeleton:(std::vector<GLKVector3>)skeleton
     firstNormal:(GLKVector3)firstNorm
{
    for (int i = 0; i < skeleton.size(); i++) {
        GLKVector3 t;
        if (i == 0) {
            t = GLKVector3Subtract(skeleton[1], skeleton[0]);
        } else if (i == (skeleton.size() - 1)) {
            t = GLKVector3Subtract(skeleton[i], skeleton[i-1]);
        } else {
            GLKVector3 v1 = GLKVector3Subtract(skeleton[i], skeleton[i-1]);
            GLKVector3 v2 = GLKVector3Subtract(skeleton[i+1], skeleton[i]);
            t = GLKVector3Lerp(v1, v2, 0.5f);
        }
        tangents.push_back(GLKVector3Normalize(t));
    }
    
    CGLA::Vec3d lastTangent = CGLA::Vec3d(tangents[0].x, tangents[0].y, tangents[0].z);
    CGLA::Vec3d lastNorm = CGLA::Vec3d(firstNorm.x, firstNorm.y, firstNorm.z);
    
    for (int i = 0; i < skeleton.size(); i++) {
        CGLA::Vec3d tangent = CGLA::Vec3d(tangents[i].x, tangents[i].y, tangents[i].z);
        CGLA::Quatd q;
        q.make_rot(lastTangent, tangent);
        CGLA::Vec3d curNorm = q.apply(lastNorm);
        GLKVector3 curNormGLK = GLKVector3Normalize(GLKVector3Make(curNorm[0], curNorm[1], curNorm[2]));
        normals.push_back(curNormGLK);
        lastTangent = tangent;
        lastNorm = curNorm;
    }
}

+(std::vector<GLKVector2>)laplacianSmoothing:(std::vector<GLKVector2>)points
                                  iterations:(int)iterations
{
    std::vector<GLKVector2> smoothed = points;
    for (int j = 0; j < iterations; j++) {
        for (int i = 1; i < points.size() - 1; i++) {
            smoothed[i] = GLKVector2Lerp(points[i-1], points[i+1], 0.5f);
        }
        points = smoothed;
    }
    return smoothed;
}

+(std::vector<GLKVector3>)laplacianSmoothing3D:(std::vector<GLKVector3>)points
iterations:(int)iterations
{
    std::vector<GLKVector3> smoothed = points;
    for (int j = 0; j < iterations; j++) {
        for (int i = 1; i < points.size() - 1; i++) {
            smoothed[i] = GLKVector3Lerp(points[i-1], points[i+1], 0.5f);
        }
        points = smoothed;
    }
    return smoothed;
}

+(void)centroids:(std::vector<GLKVector2>&)centroids
forOneFingerTouchPoint:(std::vector<GLKVector2>)touchPointsWorld
        withNextCentroidStep:(float)step
{
    //Add first centroid for pole
    float accumLen = 0.0f;
    GLKVector2 lastCentroid = touchPointsWorld[0];
    centroids.push_back(lastCentroid);
    
    //Add all other centroids
    int i = 1;
    while (i < touchPointsWorld.size()) {
        GLKVector2 centroid = touchPointsWorld[i];
        float curLen = GLKVector2Distance(lastCentroid, centroid);
        accumLen += curLen;
        
        if (accumLen >= step) {
            GLKVector2 dir = GLKVector2Normalize(GLKVector2Subtract(centroid, lastCentroid));
            GLKVector2 newCenter = GLKVector2Add(lastCentroid, GLKVector2MultiplyScalar(dir, step - (accumLen - curLen)));
            centroids.push_back(newCenter);
            accumLen = 0.0f;
            lastCentroid = newCenter;
        } else {
            lastCentroid = centroid;
            i++;
        }
    }
}

+(void)centroids3D:(std::vector<GLKVector3>&)centroids forOneFingerTouchPoint:(std::vector<GLKVector3>)touchPointsWorld
                                                         withNextCentroidStep:(float)step
{
    //Add first centroid for pole
    float accumLen = 0.0f;
    GLKVector3 lastCentroid = touchPointsWorld[0];
    centroids.push_back(lastCentroid);
    
    //Add all other centroids
    int i = 1;
    while (i < touchPointsWorld.size()) {
        GLKVector3 centroid = touchPointsWorld[i];
        float curLen = GLKVector3Distance(lastCentroid, centroid);
        accumLen += curLen;
        
        if (accumLen >= step) {
            GLKVector3 dir = GLKVector3Normalize(GLKVector3Subtract(centroid, lastCentroid));
            GLKVector3 newCenter = GLKVector3Add(lastCentroid, GLKVector3MultiplyScalar(dir, step - (accumLen - curLen)));
            centroids.push_back(newCenter);
            accumLen = 0.0f;
            lastCentroid = newCenter;
        } else {
            lastCentroid = centroid;
            i++;
        }
    }
}

+(void)centroids:(std::vector<GLKVector2>&)centroids
        ribWidth:(std::vector<float>&)ribWidth
forTwoFingerTouchPoint:(std::vector<GLKVector2>)touchPointsWorld
        withNextCentroidStep:(double)step
{
    double accumLen = 0.0f;
    //Add first centroid for pole
    GLKVector2 lastCentroid = GLKVector2Lerp(touchPointsWorld[0], touchPointsWorld[1], 0.5f);
    centroids.push_back(lastCentroid);
    
    //Add all other centroids
    int i = 2;
    while (i < touchPointsWorld.size()) {
        GLKVector2 centroid = GLKVector2Lerp(touchPointsWorld[i], touchPointsWorld[i+1], 0.5f);
        double curLen = GLKVector2Distance(lastCentroid, centroid);
        accumLen += curLen;
        
        if (accumLen >= step) {
            GLKVector2 dir = GLKVector2Normalize(GLKVector2Subtract(centroid, lastCentroid));
            GLKVector2 newCenter = GLKVector2Add(lastCentroid, GLKVector2MultiplyScalar(dir, step - (accumLen - curLen)));
            centroids.push_back(newCenter);
            ribWidth.push_back(0.5 * GLKVector2Length(GLKVector2Subtract(touchPointsWorld[i+1], touchPointsWorld[i])));
            accumLen = 0.0f;
            lastCentroid = newCenter;
        } else {
            lastCentroid = centroid;
            i += 2;
        }
    }
}

@end
