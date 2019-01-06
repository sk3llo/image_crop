part of image_crop;

const _kCropGridColumnCount = 3;
const _kCropGridRowCount = 3;
const _kCropGridColor = const Color.fromRGBO(0xd0, 0xd0, 0xd0, 0.9);
const _kCropOverlayActiveOpacity = 0.3;
const _kCropOverlayInactiveOpacity = 0.7;
const _kCropHandleColor = const Color.fromRGBO(0xd0, 0xd0, 0xd0, 1.0);
const _kCropHandleSize = 10.0;
const _kCropHandleHitSize = 48.0;
const _kCropMinFraction = 0.1;

enum _CropAction { none, moving, cropping, scaling }
enum _CropHandleSide { none, topLeft, topRight, bottomLeft, bottomRight }

class Crop extends StatefulWidget {
  final ImageProvider image;
  final double aspectRatio;

  const Crop({
    Key key,
    this.image,
    this.aspectRatio,
  })  : assert(image != null),
        super(key: key);

  Crop.file(
    File file, {
    Key key,
    double scale = 1.0,
    this.aspectRatio,
  })  : image = FileImage(file, scale: scale),
        super(key: key);

  Crop.asset(
    String assetName, {
    Key key,
    AssetBundle bundle,
    String package,
    this.aspectRatio,
  })  : image = AssetImage(assetName, bundle: bundle, package: package),
        super(key: key);

  @override
  State<StatefulWidget> createState() => CropState();

  static CropState of(BuildContext context) {
    final state = context.ancestorStateOfType(const TypeMatcher<CropState>());
    return state;
  }
}

class CropState extends State<Crop> with TickerProviderStateMixin, Drag {
  final _surfaceKey = GlobalKey();
  AnimationController _activeController;
  AnimationController _settleController;
  ImageStream _imageStream;
  ui.Image _image;
  double _scale;
  double _ratio;
  Rect _view;
  Rect _area;
  Offset _lastFocalPoint;
  _CropAction _action;
  _CropHandleSide _handle;
  double _startScale;
  Rect _startView;
  Tween<Rect> _viewTween;
  Tween<double> _scaleTween;

  double get scale => _scale;

  Rect get area {
    return _view.isEmpty
        ? null
        : Rect.fromLTRB(
            _view.left,
            _view.top,
            _view.left + _view.width * _area.width / _scale,
            _view.top + _view.height * _area.height / _scale,
          );
  }

  bool get _isEnabled => !_view.isEmpty && _image != null;

  @override
  void initState() {
    super.initState();
    _area = Rect.zero;
    _view = Rect.zero;
    _scale = 1.0;
    _ratio = 1.0;
    _lastFocalPoint = Offset.zero;
    _action = _CropAction.none;
    _handle = _CropHandleSide.none;
    _activeController = AnimationController(vsync: this)
      ..addListener(() => setState(() {}));
    _settleController = AnimationController(vsync: this)
      ..addListener(_settleAnimationChanged);
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_updateImage);
    _activeController.dispose();
    _settleController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _getImage();
  }

  @override
  void didUpdateWidget(Crop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _getImage();
    } else if (widget.aspectRatio != oldWidget.aspectRatio) {
      _area = _calculateDefaultArea(
        viewWidth: _view.width,
        viewHeight: _view.height,
        imageWidth: _image?.width,
        imageHeight: _image?.height,
      );
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _getImage(force: true);
  }

  void _getImage({bool force: false}) {
    final oldImageStream = _imageStream;
    _imageStream = widget.image.resolve(createLocalImageConfiguration(context));
    if (_imageStream.key != oldImageStream?.key || force) {
      oldImageStream?.removeListener(_updateImage);
      _imageStream.addListener(_updateImage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints.expand(),
      child: GestureDetector(
        key: _surfaceKey,
        behavior: HitTestBehavior.opaque,
        onScaleStart: _isEnabled ? _handleScaleStart : null,
        onScaleUpdate: _isEnabled ? _handleScaleUpdate : null,
        onScaleEnd: _isEnabled ? _handleScaleEnd : null,
        child: CustomPaint(
          painter: _CropPainter(
            image: _image,
            ratio: _ratio,
            view: _view,
            area: _area,
            scale: _scale,
            active: _activeController.value,
          ),
        ),
      ),
    );
  }

  void _activate() {
    _activeController.animateTo(
      1.0,
      curve: Curves.fastOutSlowIn,
      duration: const Duration(milliseconds: 250),
    );
  }

  void _deactivate() {
    _activeController.animateTo(
      0.0,
      curve: Curves.fastOutSlowIn,
      duration: const Duration(milliseconds: 250),
    );
  }

  Size get _boundaries =>
      _surfaceKey.currentContext.size -
      Offset(_kCropHandleSize, _kCropHandleSize);

  Offset _getLocalPoint(Offset point) {
    final RenderBox box = _surfaceKey.currentContext.findRenderObject();
    return box.globalToLocal(point);
  }

  void _settleAnimationChanged() {
    setState(() {
      _scale = _scaleTween.transform(_settleController.value);
      _view = _viewTween.transform(_settleController.value);
    });
  }

  Rect _calculateDefaultArea({
    int imageWidth,
    int imageHeight,
    double viewWidth,
    double viewHeight,
  }) {
    if (imageWidth == null || imageHeight == null) {
      return Rect.zero;
    }
    final width = 1.0;
    final height = (imageWidth * viewWidth * width) /
        (imageHeight * viewHeight * (widget.aspectRatio ?? 1.0));
    return Rect.fromLTWH((1.0 - width) / 2, (1.0 - height) / 2, width, height);
  }

  void _updateImage(ImageInfo imageInfo, bool synchronousCall) {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      setState(() {
        _image = imageInfo.image;
        _scale = imageInfo.scale;
        _ratio = max(
          _boundaries.width / _image.width,
          _boundaries.height / _image.height,
        );

        final viewWidth = _boundaries.width / (_image.width * _scale * _ratio);
        final viewHeight =
            _boundaries.height / (_image.height * _scale * _ratio);
        _area = _calculateDefaultArea(
          viewWidth: viewWidth,
          viewHeight: viewHeight,
          imageWidth: _image.width,
          imageHeight: _image.height,
        );
        _view = Rect.fromLTWH(
          (1.0 - viewWidth) / 2 + _area.left,
          (1.0 - viewHeight) / 2 + _area.top,
          viewWidth,
          viewHeight,
        );
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    // Allow GIF cropping (otherwise gif file will be updated on every frame)
    _imageStream.removeListener(_updateImage);
  }

  _CropHandleSide _hitCropHandle(Offset localPoint) {
    final boundaries = _boundaries;
    final viewRect = Rect.fromLTWH(
      _boundaries.width * _area.left,
      boundaries.height * _area.top,
      boundaries.width * _area.width,
      boundaries.height * _area.height,
    ).deflate(_kCropHandleSize / 2);

    if (Rect.fromLTWH(
      viewRect.left - _kCropHandleHitSize / 2,
      viewRect.top - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.topLeft;
    }

    if (Rect.fromLTWH(
      viewRect.right - _kCropHandleHitSize / 2,
      viewRect.top - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.topRight;
    }

    if (Rect.fromLTWH(
      viewRect.left - _kCropHandleHitSize / 2,
      viewRect.bottom - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.bottomLeft;
    }

    if (Rect.fromLTWH(
      viewRect.right - _kCropHandleHitSize / 2,
      viewRect.bottom - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.bottomRight;
    }

    return _CropHandleSide.none;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _activate();
    _settleController.stop(canceled: false);
    _lastFocalPoint = details.focalPoint;
    _action = _CropAction.none;
    _handle = _hitCropHandle(_getLocalPoint(details.focalPoint));
    _startScale = _scale;
    _startView = _view;
  }

  Rect _getViewInBoundaries(double scale) {
    double left = _view.left;
    double top = _view.top;

    if (left < 0.0) {
      left = 0.0;
    } else if (left > 1.0 - _view.width * _area.width / scale) {
      left = 1.0 - _view.width * _area.width / scale;
    }

    if (top < 0.0) {
      top = 0.0;
    } else if (top > 1.0 - _view.height * _area.height / scale) {
      top = 1.0 - _view.height * _area.height / scale;
    }

    return Offset(left, top) & _view.size;
  }

  double get _minimumScale {
    final scaleX = _boundaries.width * _area.width / (_image.width * _ratio);
    final scaleY = _boundaries.height * _area.height / (_image.height * _ratio);
    return max(scaleX, scaleY);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _deactivate();

    final targetScale = max(min(_scale, 2.0), _minimumScale);
    _scaleTween = Tween<double>(
      begin: _scale,
      end: targetScale,
    );

    _startView = _view;
    _viewTween = RectTween(
      begin: _view,
      end: _getViewInBoundaries(targetScale),
    );

    _settleController.value = 0.0;
    _settleController.animateTo(
      1.0,
      curve: Curves.fastOutSlowIn,
      duration: const Duration(milliseconds: 350),
    );
  }

  void _updateArea({double left, double top, double right, double bottom}) {
    var areaLeft = _area.left + (left ?? 0.0);
    var areaTop = _area.top + (top ?? 0.0);
    var areaRight = _area.right + (right ?? 0.0);
    var areaBottom = _area.bottom + (bottom ?? 0.0);

    // ensure minimum rectangle
    if (areaRight - areaLeft < _kCropMinFraction) {
      if (left != null) {
        areaLeft = areaRight - _kCropMinFraction;
      } else {
        areaRight = areaLeft + _kCropMinFraction;
      }
    }

    if (areaBottom - areaTop < _kCropMinFraction) {
      if (top != null) {
        areaTop = areaBottom - _kCropMinFraction;
      } else {
        areaBottom = areaTop + _kCropMinFraction;
      }
    }

    // adjust to aspect ratio if needed
    if (widget.aspectRatio != null && widget.aspectRatio > 0.0) {
      final width = areaRight - areaLeft;
      final height = (_image.width * _view.width * width) /
          (_image.height * _view.height * widget.aspectRatio);

      if (top != null) {
        areaTop = areaBottom - height;
        if (areaTop < 0.0) {
          areaTop = 0.0;
          areaBottom = height;
        }
      } else {
        areaBottom = areaTop + height;
        if (areaBottom > 1.0) {
          areaTop = 1.0 - height;
          areaBottom = 1.0;
        }
      }
    }

    // ensure to remain within bounds of the view
    if (areaLeft < 0.0) {
      areaLeft = 0.0;
      areaRight = _area.width;
    } else if (areaRight > 1.0) {
      areaLeft = 1.0 - _area.width;
      areaRight = 1.0;
    }

    if (areaTop < 0.0) {
      areaTop = 0.0;
      areaBottom = _area.height;
    } else if (areaBottom > 1.0) {
      areaTop = 1.0 - _area.height;
      areaBottom = 1.0;
    }

    setState(() {
      _area = Rect.fromLTRB(areaLeft, areaTop, areaRight, areaBottom);
    });
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_action == _CropAction.none) {
      if (_handle == _CropHandleSide.none) {
        _action = details.rotation == 0.0 && details.scale == 1.0
            ? _CropAction.moving
            : _CropAction.scaling;
      } else {
        _action = _CropAction.cropping;
      }
    }

    if (_action == _CropAction.cropping) {
      final delta = details.focalPoint - _lastFocalPoint;
      _lastFocalPoint = details.focalPoint;

      final dx = delta.dx / _boundaries.width;
      final dy = delta.dy / _boundaries.height;

     // Area always stays in the center of the screen when user move the handle
      if (_handle == _CropHandleSide.topLeft) {
        _updateArea(left: dx, top: dy, bottom: -dy, right: -dx);
      } else if (_handle == _CropHandleSide.topRight) {
        _updateArea(top: dy, right: dx, left: -dx, bottom: -dy);
      } else if (_handle == _CropHandleSide.bottomLeft) {
        _updateArea(left: dx, bottom: dy, top: -dy, right: -dx);
      } else if (_handle == _CropHandleSide.bottomRight) {
        _updateArea(right: dx, bottom: dy, top: -dy, left: -dx);
      }
      
    } else if (_action == _CropAction.moving) {
      final delta = _lastFocalPoint - details.focalPoint;
      _lastFocalPoint = details.focalPoint;

      setState(() {
        _view = _view.translate(
          delta.dx / (_image.width * _scale * _ratio),
          delta.dy / (_image.height * _scale * _ratio),
        );
      });
    } else if (_action == _CropAction.scaling) {
      setState(() {
        _scale = _startScale * details.scale;

        final dx = _boundaries.width *
            (1.0 - details.scale) /
            (_image.width * _scale * _ratio);
        final dy = _boundaries.height *
            (1.0 - details.scale) /
            (_image.height * _scale * _ratio);

        _view = Rect.fromLTWH(
          _startView.left - dx / 2,
          _startView.top - dy / 2,
          _startView.width,
          _startView.height,
        );
      });
    }
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect view;
  final double ratio;
  final Rect area;
  final double scale;
  final double active;

  _CropPainter({
    this.image,
    this.view,
    this.ratio,
    this.area,
    this.scale,
    this.active,
  });

  @override
  bool shouldRepaint(_CropPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.view != view ||
        oldDelegate.ratio != ratio ||
        oldDelegate.area != area ||
        oldDelegate.active != active ||
        oldDelegate.scale != scale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _kCropHandleSize / 2,
      _kCropHandleSize / 2,
      size.width - _kCropHandleSize,
      size.height - _kCropHandleSize,
    );

    canvas.save();
    canvas.translate(rect.left, rect.top);

    final paint = Paint()..isAntiAlias = false;

    if (image != null) {
      final src = Rect.fromLTWH(
        0.0,
        0.0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromLTWH(
        rect.width * area.left - image.width * view.left * scale * ratio,
        rect.height * area.top - image.height * view.top * scale * ratio,
        image.width * scale * ratio,
        image.height * scale * ratio,
      );

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0.0, 0.0, rect.width, rect.height));
      canvas.drawImageRect(image, src, dst, paint);
      canvas.restore();
    }

    paint.color = Color.fromRGBO(
        0x0,
        0x0,
        0x0,
        _kCropOverlayActiveOpacity * active +
            _kCropOverlayInactiveOpacity * (1.0 - active));
    final boundaries = Rect.fromLTWH(
      rect.width * area.left,
      rect.height * area.top,
      rect.width * area.width,
      rect.height * area.height,
    );
    canvas.drawRect(Rect.fromLTRB(0.0, 0.0, rect.width, boundaries.top), paint);
    canvas.drawRect(
        Rect.fromLTRB(0.0, boundaries.bottom, rect.width, rect.height), paint);
    canvas.drawRect(
        Rect.fromLTRB(0.0, boundaries.top, boundaries.left, boundaries.bottom),
        paint);
    canvas.drawRect(
        Rect.fromLTRB(
            boundaries.right, boundaries.top, rect.width, boundaries.bottom),
        paint);

    if (!boundaries.isEmpty) {
      _drawGrid(canvas, boundaries);
      _drawHandles(canvas, boundaries);
    }

    canvas.restore();
  }

  void _drawHandles(Canvas canvas, Rect boundaries) {
    final paint = Paint()
      ..isAntiAlias = true
      ..color = _kCropHandleColor;

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.left - _kCropHandleSize / 2,
        boundaries.top - _kCropHandleSize / 2,
        _kCropHandleSize,
        _kCropHandleSize,
      ),
      paint,
    );

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.right - _kCropHandleSize / 2,
        boundaries.top - _kCropHandleSize / 2,
        _kCropHandleSize,
        _kCropHandleSize,
      ),
      paint,
    );

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.right - _kCropHandleSize / 2,
        boundaries.bottom - _kCropHandleSize / 2,
        _kCropHandleSize,
        _kCropHandleSize,
      ),
      paint,
    );

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.left - _kCropHandleSize / 2,
        boundaries.bottom - _kCropHandleSize / 2,
        _kCropHandleSize,
        _kCropHandleSize,
      ),
      paint,
    );
  }

  void _drawGrid(Canvas canvas, Rect boundaries) {
    if (active == 0.0) return;

    final paint = Paint()
      ..isAntiAlias = false
      ..color = _kCropGridColor.withOpacity(_kCropGridColor.opacity * active)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path()
      ..moveTo(boundaries.left, boundaries.top)
      ..lineTo(boundaries.right, boundaries.top)
      ..lineTo(boundaries.right - 1, boundaries.bottom - 1)
      ..lineTo(boundaries.left, boundaries.bottom - 1)
      ..lineTo(boundaries.left, boundaries.top);

    for (var column = 1; column < _kCropGridColumnCount; column++) {
      path
        ..moveTo(
            boundaries.left + column * boundaries.width / _kCropGridColumnCount,
            boundaries.top)
        ..lineTo(
            boundaries.left + column * boundaries.width / _kCropGridColumnCount,
            boundaries.bottom - 1);
    }

    for (var row = 1; row < _kCropGridRowCount; row++) {
      path
        ..moveTo(boundaries.left,
            boundaries.top + row * boundaries.height / _kCropGridRowCount)
        ..lineTo(boundaries.right - 1,
            boundaries.top + row * boundaries.height / _kCropGridRowCount);
    }

    canvas.drawPath(path, paint);
  }
}
