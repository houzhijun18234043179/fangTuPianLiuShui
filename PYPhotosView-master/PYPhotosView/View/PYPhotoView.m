//  代码地址: https://github.com/iphone5solo/PYPhotosView
//  代码地址: http://code4app.com/thread-8612-1-1.html
//  Created by CoderKo1o.
//  Copyright © 2016年 iphone5solo. All rights reserved.
//

#import "PYPhotoView.h"
#import "UIImageView+WebCache.h"
#import "PYPhoto.h"
#import "PYPhotosView.h"
#import "PYConst.h"
#import "PYPhotosReaderController.h"
#import "PYPhotoCell.h"
#import "PYDALabeledCircularProgressView.h"
#import "MBProgressHUD+PY.h"
#import "PYMoviePlayerView.h"
#import "PYMoviePlayerController.h"
#import "PYMovie.h"

// cell的宽
#define PYPhotoCellW (self.photoCell.py_width > 0 ? self.photoCell.py_width : PYScreenW)
// cell的高
#define PYPhotoCellH (self.photoCell.py_height > 0 ? self.photoCell.py_height : PYScreenH)

// 旋转角为PI的整数倍
#define PYHorizontal (ABS(self.rotation) < 0.01 || ABS(self.rotation - M_PI) < 0.01 || ABS(self.rotation - M_PI * 2) < 0.01)

// 旋转角为90°或者270°
#define PYVertical (ABS(self.rotation - M_PI_2) < 0.01 || ABS(self.rotation - M_PI_2 * 3) < 0.01)

@interface PYPhotoView ()<UIActionSheetDelegate, UIGestureRecognizerDelegate>
/** 单击手势 */
@property (nonatomic, weak) UIGestureRecognizer *singleTap;

/** photoCell的单击手势 */
@property (nonatomic, weak) UIGestureRecognizer *photoCellSingleTap;

/** 原始锚点 */
@property (nonatomic, assign) CGPoint originAnchorPoint;

/** 记录加载链接 */
@property (nonatomic, strong) NSURL *lastUrl;
/** 旋转的角度 */
@property (nonatomic, assign) CGFloat rotation;

/** 手势状态 */
@property (nonatomic, assign) UIGestureRecognizerState state;

/** 加载失败显示图片 */
@property (nonatomic, weak) UIImageView *loadFailureView;

/** 删除图片 */
@property (nonatomic, weak) UIImageView *deleteImageView;

@end

@implementation PYPhotoView

- (instancetype)init
{
    if (self = [super init]) {
        // 运行与用户交互
        self.userInteractionEnabled = YES;
        
        // photoView添加单击手势
        UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageDidClicked:)];
        [self addGestureRecognizer:singleTap];
        self.singleTap = singleTap;
        
        // 监听通知
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(collectionViewDidScroll:) name:PYCollectionViewDidScrollNotification object:nil];
        
        // 添加进度条
        PYDALabeledCircularProgressView *progressView = [[PYDALabeledCircularProgressView alloc] init];
        progressView.py_size = CGSizeMake(100, 100);
        progressView.hidden = YES;
        [self addSubview:progressView];
        self.progressView = progressView;
        
        // 添加加载失败
        UIImageView *loadFailureView = [[UIImageView alloc] initWithFrame:progressView.frame];
        loadFailureView.image = PYLoadFailureImage;
        loadFailureView.hidden = YES;
        [self addSubview:loadFailureView];
        self.loadFailureView = loadFailureView;
        
        // 设置原始锚点
        self.originAnchorPoint = self.layer.anchorPoint;
        
        // 默认放大倍数和旋转角度
        self.scale = 1.0;
        self.rotation = 0.0;
        
        // 删除图片
        UIImageView *deleteImageView = [[UIImageView alloc] init];
        [deleteImageView setImage:PYDeleteImage];
        deleteImageView.py_size = CGSizeMake(15, 15);
        deleteImageView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5];
        deleteImageView.userInteractionEnabled = YES;
        [deleteImageView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(deleteImage)]];
        // 默认隐藏
        deleteImageView.hidden = YES;
        [self addSubview:deleteImageView];
        self.deleteImageView = deleteImageView;
        // 取消自动布局
        self.autoresizingMask = UIViewAutoresizingNone;
        // 设置图片为默认图片
        self.image = PYPlaceholderImage;
    }
    return self;
}

- (PYMoviePlayerController *)playerController
{
    if (!_playerController) {
        _playerController = [[PYMoviePlayerController alloc] init];
    }
    return _playerController;
}

- (void)dealloc
{
    self.playerController = nil;
    // 移除通知
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// 监听transform
- (void)setTransform:(CGAffineTransform)transform
{
    [super setTransform:transform];
    
    // 如果手势没结束、没有放大、旋转手势，返回
    if (self.isRotationGesture) return;
    
    // 判断是否放大
    if (self.py_width >= (PYPhotoCellW - 0.01) || self.py_height >= (PYPhotoCellH - 0.01)) { // 超出屏幕
        // 修改contentScrollView的属性
        UIScrollView *contentScrollView = self.photoCell.contentScrollView;
        contentScrollView.py_height = self.py_height < PYPhotoCellH ? self.py_height : PYPhotoCellH;
        contentScrollView.py_width = self.py_width < PYPhotoCellW ? self.py_width : PYPhotoCellW;
        contentScrollView.contentSize = self.py_size;
        contentScrollView.contentInset = UIEdgeInsetsMake(-self.py_y, -self.py_x, self.py_y, self.py_x);
        contentScrollView.scrollEnabled = YES;
        contentScrollView.center = CGPointMake(PYPhotoCellW * 0.5, PYPhotoCellH * 0.5);
    } else {
        self.photoCell.contentScrollView.scrollEnabled = NO;
    }
    
}

// 添加指定的手势
- (void)addGestureRecognizers
{
    // photoCell添加双击手势
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageDidDoubleClicked:)];
    [doubleTap setNumberOfTapsRequired:2];
    [self.photoCell addGestureRecognizer:doubleTap];
    
    // photoCell单击双击共存时，单击失效
    [self.photoCellSingleTap requireGestureRecognizerToFail:doubleTap];
    
    // photoCell添加长按手势
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(imageDidLongPress:)];
    [self.photoCell addGestureRecognizer:longPress];
    
    // photoCell添加捏合手势
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(imageDidPinch:)];
    [self.photoCell addGestureRecognizer:pinch];
    
    // photoCell添加旋转手势
    UIRotationGestureRecognizer *rotation = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(photoDidRotation:)];
    [self.photoCell addGestureRecognizer:rotation];
    
    if (self.isBig) { // 预览状态，支持双击手势，支持加载进度指示器
        // 添加双击手势
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageDidDoubleClicked:)];
        [doubleTap setNumberOfTapsRequired:2];
        [self addGestureRecognizer:doubleTap];
        // 单击双击共存时，避免双击失效
        [self.singleTap requireGestureRecognizerToFail:doubleTap];
    }
}

// 移除指定的手势
- (void)removeGestureRecognizers
{
    // 删除photoCell的除单击以外的手势
    for (UIGestureRecognizer *gr in self.photoCell.gestureRecognizers) {
        if (!([gr isKindOfClass:[UITapGestureRecognizer class]] && ((UITapGestureRecognizer *)gr).numberOfTapsRequired == 1)) { // 只要不是单击手势，都移除
            [self.photoCell removeGestureRecognizer:gr];
        }
    }
    // 移除photoView的双击手势
    for (UIGestureRecognizer *gr in self.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]] && ((UITapGestureRecognizer *)gr).numberOfTapsRequired == 2) { // 双击手势移除
            [self removeGestureRecognizer:gr];
        }
    }
}

- (void)setPhotoCell:(PYPhotoCell *)photoCell
{
    _photoCell = photoCell;
    
    // photoCell添加单击手势
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageDidClicked:)];
    [photoCell addGestureRecognizer:singleTap];
    self.photoCellSingleTap = singleTap;
}

- (void)setImage:(UIImage *)image
{
    if (!image) return;
    
    CGFloat height = PYPhotoCellW * image.size.height / image.size.width;
    self.contentMode = UIViewContentModeScaleAspectFill;
    self.clipsToBounds = YES;
    if (height > PYPhotoCellH) { // 长图
        if (self.isBig) { // 预览状态
            self.py_size = CGSizeMake(PYPhotoCellW, PYPhotoCellW * image.size.height / image.size.width);
        } else {
            self.py_size = CGSizeMake(PYPhotoCellW, PYPhotoCellH);
            // 显示最上面的
            UIGraphicsBeginImageContextWithOptions(self.py_size,YES, 0.0);
            // 绘图
            CGFloat width = self.py_width;
            CGFloat height = width * image.size.height / image.size.width;
            [image drawInRect:CGRectMake(0, 0, width, height)];
            // 保存图片
            image = UIGraphicsGetImageFromCurrentImageContext();
            // 关闭上下文
            UIGraphicsEndImageContext();
        }
    }
    [super setImage:image];

    CGFloat width = PYPhotoCellW;
    originalSize = self.image.size;
    if (PYPhotoCellW > PYPhotoCellH) { //  横屏
        if (originalSize.width > originalSize.height * 2) { // 原始图宽大于高的两倍
            width = PYPhotoCellW;
            height = width * originalSize.height / originalSize.width;
        } else {
            height = PYPhotoCellH;
            width = height * originalSize.width / originalSize.height;
        }
    }
    self.py_size = self.isBig ? CGSizeMake(width, height) : self.image.size;
    // 设置scrollView的大小
    self.photoCell.contentScrollView.py_size = self.py_size;
    self.photoCell.contentScrollView.center = CGPointMake(PYPhotoCellW * 0.5, PYPhotoCellH * 0.5);
    self.photoCell.contentScrollView.contentSize = self.py_size;
    // 进度条居中
    self.progressView.center = CGPointMake(self.py_width * 0.5, self.py_height * 0.5);
}

- (void)setMovie:(PYMovie *)movie
{
    if (!movie) return;
    
    _movie = movie;
    NSURL *contentUrl = movie.url;
    // 链接非法
    if (contentUrl.lastPathComponent.length == 0 || ![[UIApplication sharedApplication] canOpenURL:contentUrl]) {
        self.loadFailureView.hidden = NO;
        self.userInteractionEnabled = NO;
        return;
    }
    // 链接合法
    dispatch_async(dispatch_get_global_queue(0, 0) , ^{
       //  判断是否是视频连接
        AVAsset *asset = [AVURLAsset URLAssetWithURL:contentUrl options:nil];
        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        BOOL hasVideoTrack = [tracks count] > 0;
        if (!hasVideoTrack) {
            dispatch_async(dispatch_get_main_queue(), ^{ // 刷新界面
                self.loadFailureView.hidden = NO;
                self.userInteractionEnabled = NO;
                self.playerController.noVideo = YES;
                self.playerController = nil;
            });
        }
    });

    self.userInteractionEnabled = YES;
    self.photo = NULL;
    self.isMovie = YES;
    // 将模型传给phtosView
    self.playerController.movie = movie;
    self.photosView.movie = self.playerController.movie;
    self.playerController.photoView = self;
    [self addSubview:self.playerController.view];
    if (self.isBig) { // 大图
        self.py_size = CGSizeMake(PYScreenW, PYScreenH);
    } else {
        self.py_size = self.photo.originalSize;
    }
    
    self.playerController.playView.hidden = !self.isBig;
    self.playerController.view.userInteractionEnabled = self.isBig;
    self.playerController.shouldAutoplay = self.isBig;
}

// 如果有旋转，需要修改锚点
- (void)setNewAnchorPoint:(CGPoint)anchorPoint getureRecognizer:(UIGestureRecognizer *)gr
{
    // 获取旋转角
    CGFloat angle = self.rotation;
    // 点击的view为PYPhotoCell且scrollView旋转就要修改锚点
    if ([[gr view] isKindOfClass:[PYPhotoCell class]]) { // 点击PYPhotoCell
        // 修改锚点
        if (ABS(angle - M_PI_2) <= 0.01) { // 旋转角为90°
            anchorPoint = CGPointMake(anchorPoint.y , 1 - anchorPoint.x);
        } else if (ABS(angle - M_PI_2 * 3) <= 0.01) { // 旋转角为270°
            anchorPoint = CGPointMake(1 - anchorPoint.y,  anchorPoint.x);
        } else if (ABS(angle - M_PI) <= 0.01) { // 旋转角为180°
            anchorPoint = CGPointMake(1 - anchorPoint.x, 1 - anchorPoint.y);
        }
        // 重新设置锚点
        [self py_setAnchorPoint:anchorPoint forView:self];
     }
}

// 记录预览时的最原始大小（未伸缩\旋转）
static CGSize originalSize;

// 旋转手势
- (void)photoDidRotation:(UIRotationGestureRecognizer *)rotation
{
    // 记录当前手势
    self.state = rotation.state;
    self.rotationGesture = YES;
    
    // 设置contentScrollView
    UIScrollView *contentScrollView = self.photoCell.contentScrollView;
    contentScrollView.contentOffset = CGPointZero;
    contentScrollView.contentInset = UIEdgeInsetsZero;
    contentScrollView.frame = CGRectMake(0, 0, PYPhotoCellW, PYPhotoCellH);
    self.center = CGPointMake(PYPhotoCellW * 0.5, PYPhotoCellH * 0.5);
    
    // 计算旋转角度
    self.transform = CGAffineTransformRotate(self.transform, rotation.rotation);
    
    if (rotation.state == UIGestureRecognizerStateEnded
        || rotation.state == UIGestureRecognizerStateFailed
        || rotation.state == UIGestureRecognizerStateCancelled) { // 手势结束\失败\取消
        
        CGAffineTransform temp = CGAffineTransformScale(self.transform, 1 / self.scale, 1 / self.scale);
        
        originalSize = self.photo.originalSize;
        // 获取角度
        CGFloat angle = acosf(temp.a);
        if (ABS(asinf(self.transform.b) + M_PI_2) < 0.01) { // 旋转270°
            angle += M_PI;
        }
        // 获取旋转因子
        CGFloat factor = ((int)(temp.b + 0.5)) == 1 ? 1 : -1;
        // 旋转后的宽高
        __block CGFloat width = 0;
        __block CGFloat height = 0;
        if (originalSize.width > originalSize.height * 2 || PYPhotoCellW > PYPhotoCellH) { // （原始图片）宽大于高的两倍(竖屏) 或者横屏
            height = PYPhotoCellH;
            width = height * originalSize.height / originalSize.width;
        } else { // （原始图片）高大于宽
            height = PYPhotoCellW * originalSize.width / originalSize.height > PYPhotoCellH ? PYPhotoCellH : PYPhotoCellW * originalSize.width / originalSize.height;
            width = PYPhotoCellW;
        }
        
        // 判断旋转角度
        if (angle < M_PI_4 || angle > M_PI * 7 / 4) { // 旋转角度在0°~45°/315°~360°之间
            angle = 0;
        } else if (angle < M_PI * 3 / 4) { // 旋转角度在45°~135°之间
            angle = M_PI_2;
        } else if (angle < M_PI * 5 / 4) { // 旋转角度在135°~225°之间
            angle = M_PI;
        } else if (angle < M_PI * 7 / 4) { // 旋转角度在225°~315°之间
            angle = M_PI_2 * 3 ;
        }
        // 默认为0.25秒
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            self.transform = CGAffineTransformMakeRotation(angle * factor);
            self.rotation = acosf(self.transform.a);
            if (ABS(asinf(self.transform.b) + M_PI_2) < 0.01) { // 旋转270°
                self.rotation += M_PI;
            }
            // 判断最终旋转角度
            if (PYHorizontal) { // 旋转角为PI的倍数
                height = originalSize.height > PYPhotoCellH ? PYPhotoCellH : originalSize.height;
                width = originalSize.width > PYPhotoCellW ? PYPhotoCellW : originalSize.width;
            }
            
            self.photo.verticalWidth = width;
            self.py_origin = CGPointZero;
            self.py_size = CGSizeMake(width, height);
            contentScrollView.py_size = CGSizeMake(self.py_width > PYPhotoCellW ? PYPhotoCellW : self.py_width, self.py_height > PYPhotoCellH ? PYPhotoCellH : self.py_height);
            contentScrollView.contentSize = self.py_size;
            contentScrollView.center = CGPointMake(PYPhotoCellW * 0.5, PYPhotoCellH * 0.5);
            contentScrollView.contentOffset = CGPointZero;
        } completion:^(BOOL finished) {
            self.rotationGesture = NO;
        }];
    }
    // 复位（如果不复位，会导致乱转）
    rotation.rotation = 0;
}

// 捏合手势
- (void)imageDidPinch:(UIPinchGestureRecognizer *)pinch
{
    // 获取锚点
    CGPoint anchorPoint = [self py_setAnchorPointBaseOnGestureRecognizer:pinch];
    // 设置新的锚点
    [self setNewAnchorPoint:anchorPoint getureRecognizer:pinch];
    
    // 记录手势
    self.state = pinch.state;
    self.rotationGesture = NO;

    self.transform = CGAffineTransformScale(self.transform, pinch.scale, pinch.scale);
    // 复位
    pinch.scale = 1;
    
    if (pinch.state == UIGestureRecognizerStateEnded
        || pinch.state == UIGestureRecognizerStateFailed
        || pinch.state == UIGestureRecognizerStateCancelled) { // 手势结束\取消\失败
        // 判断是否缩小
        CGFloat scale = 1;
        
        if (PYHorizontal) { // 旋转角为PI的整数倍 并且竖屏
            if (self.py_width <= self.photo.verticalWidth) { // 缩小了(旋转0°、180°、360°)
                // 放大
                scale = self.photo.verticalWidth / self.py_width;
            } else if (self.py_width > self.photo.verticalWidth * PYPreviewPhotoMaxScale) { // 最大放大3倍
                scale = self.photo.verticalWidth * PYPreviewPhotoMaxScale / self.py_width;
            }
        } else if (PYVertical) { // 旋转角为90°或者270°
            if (originalSize.width > originalSize.height * 2) { // image高和屏幕高一样
                if (self.py_height < PYPhotoCellH) { // 比原来小了
                    scale = PYPhotoCellH / self.py_height;
                } else if (self.py_height > PYPhotoCellH * PYPreviewPhotoMaxScale) { // 超过了最大倍数
                    scale = PYPhotoCellH * PYPreviewPhotoMaxScale / self.py_height;
                }
            } else { // image宽和屏幕一样
                if (self.py_width < self.photo.verticalWidth) { // 比原来小了
                    scale = self.photo.verticalWidth / self.py_width;
                } else if (self.py_width > self.photo.verticalWidth * PYPreviewPhotoMaxScale) { // 超过了最大倍数
                    scale = self.photo.verticalWidth * PYPreviewPhotoMaxScale / self.py_width;
                }
            }
        }
      
        // 复位
        [UIView animateWithDuration:0.25  delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            self.transform = CGAffineTransformScale(self.transform, scale, scale);
        } completion:^(BOOL finished) {
            // 恢复锚点
            [self py_setAnchorPoint:CGPointMake(0.5, 0.5) forView:self];
            // 记录放大的倍数
            self.scale = self.py_width / self.photo.verticalWidth;
        }];
    }
}

// 长按手势
- (void)imageDidLongPress:(UITapGestureRecognizer *)longPress
{
    if (longPress.state == UIGestureRecognizerStateBegan) {  // 长按结束
        // 跳出提示
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"取消" destructiveButtonTitle:nil otherButtonTitles:@"保存到相册", @"发送给朋友", nil];
        sheet.delegate = self;
        [sheet showInView:self.window];
    }
}

// 双击手势（只有图片在预览状态时才支持）
- (void)imageDidDoubleClicked:(UITapGestureRecognizer *)singleTap
{
    // 设置锚点
    CGPoint anchorPoint = [self py_setAnchorPointBaseOnGestureRecognizer:singleTap];
    // 设置新锚点
    [self setNewAnchorPoint:anchorPoint getureRecognizer:singleTap];

    // 放大倍数（默认为放大）
    CGFloat scale = 2.0;
    if ((self.py_width - self.photo.verticalWidth) > 0.01) scale = self.photo.verticalWidth / self.py_width;
    
    [UIView animateWithDuration:0.25  delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.transform = CGAffineTransformScale(self.transform, scale, scale);
    } completion:^(BOOL finished) {
        // 恢复锚点
        [self py_setAnchorPoint:CGPointMake(0.5, 0.5) forView:self];
        // 记录放大倍数
        self.scale = self.py_width / self.photo.verticalWidth;
    }];
}

// 单击手势
- (void)imageDidClicked:(UITapGestureRecognizer *)sender
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (self.photosView.photosState == PYPhotosViewStateDidCompose) { // 已发布
        if (self.isMovie) { // 设置视频封面
            self.contentMode = UIViewContentModeScaleToFill;
            // 封面图还没加载完 不允许点击
            if (!self.playerController.playView.movieImage) return;
            // 设置封面图
            self.image = self.playerController.playView.movieImage;
            self.py_size = CGSizeMake(self.photosView.photoWidth, self.photosView.photoHeight);
        }
        if (!self.isBig) { // 放大
            // 遍历所有photoFrame记录原始frame
            for (PYPhotoView *photoView in self.photosView.subviews) {
                photoView.orignalFrame = photoView.frame;
            }
            // 发出通知
            userInfo[PYBigImageDidClikedNotification] = self;
            NSNotification *notification = [[NSNotification alloc] initWithName:PYBigImageDidClikedNotification object:self.photosView userInfo:userInfo];
            [center postNotification:notification];
        } else { // 缩小
            // 隐藏图片加载失败
            self.loadFailureView.hidden = YES;
            // 移除进度条
            [self.progressView removeFromSuperview];
            // 不可以双击
            userInfo[PYSmallgImageDidClikedNotification] = self;
            NSNotification *notification = [[NSNotification alloc] initWithName:PYSmallgImageDidClikedNotification object:self.photosView userInfo:userInfo];
            [center postNotification:notification];
        }
    } else if (self.photosView.photosState == PYPhotosViewStateWillCompose) { // 未发布
        if (self.isPreview) { // 正在预览
                NSNotification *notifaction = [[NSNotification alloc] initWithName:PYChangeNavgationBarStateNotification object:self.photosView userInfo:userInfo];
                [center postNotification:notifaction];
        } else { // 将要预览
            // 进入预览界面
            userInfo[PYPreviewImagesDidChangedNotification] = self;
            NSNotification *notifaction = [[NSNotification alloc] initWithName:PYPreviewImagesDidChangedNotification object:self.photosView userInfo:userInfo];
            [center postNotification:notifaction];
        }
    }
}

// 设置图片（图片来自网络）
- (void)setPhoto:(PYPhoto *)photo
{
    _photo = photo;
    
    self.progressView.hidden = YES;
    
    // 移除手势
    [self removeGestureRecognizers];
    
    // 视频为空
    self.movie = nil;
    
    // 设置已经加载的进度
    [self.progressView setProgress:photo.progress animated:NO];
    
    // 设置链接(默认设置为缩略图)
    NSString *urlStr = photo.thumbnail_pic ? photo.thumbnail_pic : photo.original_pic;
    UIImage *placeholdeerImage = PYPlaceholderImage;
    if (self.isBig) { // 图片浏览（放大）, 原图具有优先级
        // 获取缩略图
        placeholdeerImage = self.photo.thumbnailImage ? self.photo.thumbnailImage : PYPlaceholderImage;
        urlStr = photo.original_pic ? photo.original_pic : photo.thumbnail_pic;
    } else {
        if (self.photo.originalImage) { // 原图下载了
            urlStr = photo.original_pic ? photo.original_pic : photo.thumbnail_pic;
        }
    }
    
    NSURL *url = [NSURL URLWithString:urlStr];
    [self sd_setImageWithURL:url placeholderImage:placeholdeerImage options:0 progress:^(NSInteger receivedSize, NSInteger expectedSize) {
        if (self.isBig) {
            // 获取图片链接
            NSString *imageUrl = [[self sd_imageURL] absoluteString];
            for (PYPhoto *photo in self.photosView.photos) {
                if ([imageUrl isEqualToString:photo.original_pic] || (!photo.original_pic &&
                    [imageUrl isEqualToString:photo.thumbnail_pic])) { // 找到模型,设置下载进度
                    CGFloat progress = 1.0 * receivedSize / expectedSize;
                    if (progress >= photo.progress) { // 大于模型进度
                        photo.progress = progress;
                    }
                }
            }
            if ([imageUrl isEqualToString:self.photo.original_pic] || (!self.photo.original_pic &&
                [imageUrl isEqualToString:self.photo.thumbnail_pic])) { // 图片为当前PYPhotoView的图片
                self.progressView.hidden = NO;
                [self.progressView setProgress:self.photo.progress animated:YES];
            }
        }
    } completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
        self.progressView.hidden = YES;
        if (image && ([[imageURL absoluteString] isEqualToString:self.photo.thumbnail_pic] ||
                      [[imageURL absoluteString] isEqualToString:self.photo.original_pic])) { // 图片为当前PYPhotoView的图片并且不是占位图（占位图 image会为null）
            // 允许手势
            [self addGestureRecognizers];
            // 记录原始大小
            self.photo.originalSize = CGSizeMake(self.py_width, self.py_width * image.size.height / image.size.width);
            // 记录未旋转的宽度或者旋转完成时的宽度
            self.photo.verticalWidth = self.photo.originalSize.width;
            if (!self.isBig) {
                self.photo.thumbnailImage = image;
            } else {
                self.photo.originalImage = image;
                self.photo.progress = 1.0;
            }
        }
        // 图片加载失败(是否隐藏)
        self.loadFailureView.hidden = !self.isBig || image;
    }];
}

// 设置本地图片（未发布）
- (void)setImages:(NSMutableArray *)images
{
    _images = images;
    
    self.deleteImageView.hidden = images.count == 0;
}

// 删除图片
- (void)deleteImage
{
    [self.images removeObjectAtIndex:self.tag];
    self.photosView.images = self.images;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    // 判断最终旋转角度如果为270、90
    if ((PYVertical && PYPhotoCellH > PYPhotoCellW) || (PYHorizontal && PYPhotoCellW > PYPhotoCellH)) return;
    CGFloat width = PYScreenW;
    CGFloat height =  width * self.image.size.height / self.image.size.width;
    if (self.isBig || self.isPreview) { // 预览状态
        if (height > PYScreenH) { // 长图
            UIScrollView *contentScrollView = self.photoCell.contentScrollView;
            contentScrollView.scrollEnabled = YES;
            contentScrollView.contentSize = PYPhotoCellW > PYPhotoCellH ? CGSizeMake(height, width) : CGSizeMake(width, height);
            contentScrollView.scrollsToTop = YES;
            contentScrollView.frame = PYPhotoCellW > PYPhotoCellH ? CGRectMake(0, 0, PYScreenH, PYScreenW) : CGRectMake(0, 0, PYScreenW, PYScreenH);
        } else {
            self.photoCell.contentScrollView.contentSize = self.py_size;
            self.photoCell.contentScrollView.scrollEnabled = NO;
        }
    }
    
    // 设置删除图片位置
    self.deleteImageView.py_x = self.py_width - self.deleteImageView.py_width;
    // 设置加载进程和加载错误图片位置
    self.progressView.center = CGPointMake(self.py_width * 0.5, self.py_height * 0.5);
    self.loadFailureView.center = self.progressView.center;
    if (self.isMovie) { // 含有视频
        // 设置视频播放范围
        self.playerController.view.frame = self.playerController.playView.frame = self.bounds;
        // 设置播放按钮的位置
        self.playerController.playButtonView.center = CGPointMake(self.py_width * 0.5, self.py_height * 0.5);
        // 设置视频时间label的位置
        self.playerController.durationLabel.py_origin = CGPointMake(PYMargin, self.py_height - self.playerController.durationLabel.py_height - PYMargin);
    }
}

// 监听滚动，判断cell是否在屏幕上，初始化cell
- (void)collectionViewDidScroll:(NSNotification *)noti
{
    // 取出参数
    NSDictionary *info = noti.userInfo;
    UIScrollView *scrollView = info[PYCollectionViewDidScrollNotification];
    // 刷新进度条的进度
    
    if (((self.photoCell.py_x >= scrollView.contentOffset.x + scrollView.py_width) || (CGRectGetMaxX(self.photoCell.frame) < scrollView.contentOffset.x)) && (self.py_width >= PYPhotoCellW || self.photoCell.contentScrollView.transform.a)) { // 不在屏幕上并且有缩放或者旋转，就要初始化
        [self.progressView setProgress:0.0 animated:NO];
        self.rotation = 0.0;
        self.scale = 1.0;
        self.transform = CGAffineTransformIdentity;
        self.py_height = PYPhotoCellW * self.py_height / self.py_width;
        self.py_width = PYPhotoCellW;
        UIScrollView *contentScrollView = self.photoCell.contentScrollView;
        contentScrollView.contentSize = self.py_size;
        contentScrollView.py_size = self.py_size;
        contentScrollView.contentOffset = CGPointZero;
        contentScrollView.contentInset = UIEdgeInsetsZero;
        contentScrollView.transform = CGAffineTransformIdentity;
        contentScrollView.scrollEnabled = NO;
    }
}

#pragma mark - PYAcitonSheetDeleagate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 0) {
        NSLog(@"保存到相册");
        UIImageWriteToSavedPhotosAlbum(self.image, self, @selector(image: didFinishSavingWithError: contextInfo:), nil);
    } else if(buttonIndex == 1) {
        NSLog(@"分享给朋友");
    } else if (buttonIndex == 2) {
        NSLog(@"取消");
    }
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    error ? [MBProgressHUD py_showError:@"保存失败" toView:nil] : [MBProgressHUD py_showSuccess:@"保存成功" toView:nil];
}

@end
