import 'dart:math' as math;
import 'dart:typed_data';
import 'asr_assets.dart';

enum Deviation { ok, minor, major }

Deviation deviationFor(double probCorrect) {
  if (probCorrect >= 0.40) return Deviation.ok;
  if (probCorrect >= 0.30) return Deviation.minor;
  return Deviation.major;
}

/// Dart re-implementation of `tajweed/head_scorer.py`'s `PronunciationHead`
/// forward pass: concat(pooled encoder feature (512), token embedding (64),
/// fixed per-token phonology feature (16)) -> 4-layer MLP (GELU) -> sigmoid.
/// Weights are the exact checkpoint values (see asr_assets.dart), so this
/// must mirror the reference architecture exactly, not just approximate it.
class PronunciationHead {
  final PronunciationHeadWeights w;
  PronunciationHead(this.w);

  /// [encFeature]: 512-dim encoder_output frames mean-pooled over the
  /// token's aligned interval. Returns P(pronounced correctly).
  double score(Float32List encFeature, int tokenId) {
    final emb = Float32List(64);
    final embBase = tokenId * 64;
    for (var i = 0; i < 64; i++) {
      emb[i] = w.tokEmb[embBase + i];
    }
    final feat = Float32List(16);
    final featBase = tokenId * 16;
    for (var i = 0; i < 16; i++) {
      feat[i] = w.featureTable[featBase + i];
    }

    // in_dim = 512 + 64 + 16 = 592
    final x = Float32List(592);
    x.setRange(0, 512, encFeature);
    x.setRange(512, 576, emb);
    x.setRange(576, 592, feat);

    final h0 = _gelu(_linear(x, w.w0, w.b0, 592, 1024));
    final h1 = _gelu(_linear(h0, w.w1, w.b1, 1024, 512));
    final h2 = _gelu(_linear(h1, w.w2, w.b2, 512, 256));
    final logit = _linear(h2, w.w3, w.b3, 256, 1)[0];
    return 1.0 / (1.0 + math.exp(-logit));
  }

  Float32List _linear(Float32List x, Float32List weight, Float32List bias, int inDim, int outDim) {
    final out = Float32List(outDim);
    for (var o = 0; o < outDim; o++) {
      var sum = bias[o];
      final base = o * inDim;
      for (var i = 0; i < inDim; i++) {
        sum += weight[base + i] * x[i];
      }
      out[o] = sum;
    }
    return out;
  }

  Float32List _gelu(Float32List x) {
    // Exact (erf-based) GELU, matching torch.nn.GELU()'s default.
    for (var i = 0; i < x.length; i++) {
      x[i] = (0.5 * x[i] * (1.0 + _erf(x[i] / math.sqrt2))).toDouble();
    }
    return x;
  }

  // Abramowitz-Stegun 7.1.26 approximation (max error ~1.5e-7).
  double _erf(double x) {
    final sign = x < 0 ? -1.0 : 1.0;
    x = x.abs();
    const a1 = 0.254829592;
    const a2 = -0.284496736;
    const a3 = 1.421413741;
    const a4 = -1.453152027;
    const a5 = 1.061405429;
    const p = 0.3275911;
    final t = 1.0 / (1.0 + p * x);
    final y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-x * x);
    return sign * y;
  }
}
