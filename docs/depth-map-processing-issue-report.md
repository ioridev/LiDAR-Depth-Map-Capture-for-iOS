# Depth Map Processing Issue Report

## 概要

本レポートは、DepthCameraアプリケーションにおいて発生した深度マップの処理と保存に関する問題の調査・解決過程を記録したものです。

**発生日**: 2025年6月23日  
**影響範囲**: PromptDA深度推定を使用した際の画像保存機能  
**ステータス**: 解決済み

## 問題の症状

### 初期の問題
1. **Float to UInt8変換時のクラッシュ**
   - 対象物が近すぎる場合に`Thread 1: Fatal error: Float value cannot be converted to UInt8 because it is either infinite or NaN`エラーが発生
   - 深度値がNaNまたは無限大の場合の処理が不足

2. **保存画像の破損**
   - TIFFファイルに斜めの線が入る
   - PNG画像が完全に破損（ぐしゃぐしゃ）
   - プレビューは正常に表示されるが、保存時のみ問題発生

### 調査で判明した詳細
- PromptDAの出力: 252×182ピクセル（横長）
- ARKitの深度マップ: 192×256ピクセル（縦長）
- bytesPerRowにパディングが含まれる（例: 1024バイト vs 期待値1008バイト）

## 調査過程

### Phase 1: NaN/Infinite値の処理
最初に対処した問題は、深度値の変換時のクラッシュでした。

```swift
// 修正前
let pixel = UInt8(normalizedDepth * 255.0)

// 修正後
let validDepth = depth.isNaN || depth.isInfinite ? 0.0 : depth
let normalizedDepth = min(max(validDepth / 5.0, 0.0), 1.0)
let pixel = UInt8(normalizedDepth * 255.0)
```

### Phase 2: 画像保存の破損調査

1. **最初の仮説**: 解像度の不一致
   - PromptDAとARKitで異なるサイズ
   - リサイズ処理を追加 → 問題解決せず

2. **二番目の仮説**: bytesPerRowの処理ミス
   - パディングを考慮した処理に修正
   - プレビューでは正しく処理していたが、保存関数では不適切だった

3. **三番目の仮説**: テンソル形状の解釈ミス
   - [1, 182, 252]を[batch, width, height]として解釈
   - 転置処理を追加 → さらに悪化

## 根本原因

**プレビューと保存で異なるdepthMapを使用していた**ことが根本原因でした。

### 問題のあったコード構造

```swift
// プレビュー時
if let promptDADepth = estimator.estimateDepth(...) {
    latestDepthMap = promptDADepth  // キャッシュに保存
    processDepthMap(promptDADepth)   // 表示処理
}

// 保存時（問題のあった実装）
func saveDepthMap() {
    if let promptDADepth = estimator.estimateDepth(...) {  // 新たに生成！
        depthMapToSave = promptDADepth
    }
}
```

### 問題の詳細
1. プレビュー時にPromptDAで生成したdepthMapを`latestDepthMap`に保存
2. 保存時に**再度**PromptDAを実行して新しいdepthMapを生成
3. 異なるタイミング・条件で生成されたため、データが不整合

## 解決方法

### 最終的な修正

```swift
func saveDepthMap() {
    // Simply use the current latestDepthMap that was used for preview
    guard let depthMap = latestDepthMap, let image = latestImage else {
        print("Depth map or image is not available.")
        return
    }
    // 以下、保存処理...
}
```

プレビューで使用した同じdepthMapを保存に使用することで、一貫性を確保しました。

### その他の改善

1. **16ビットPNG保存オプションの追加**
   - TIFFに加えて、より汎用的なPNG形式での保存も実装
   - 深度範囲の自動正規化機能付き

2. **bytesPerRow処理の統一**
   ```swift
   let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size
   let depth = floatBuffer?[y * floatsPerRow + x]
   ```

3. **デバッグログの追加**
   - 問題調査を容易にするための詳細なログ出力

## 技術的な学び

### 1. CVPixelBufferのメモリレイアウト
- bytesPerRowは実際の画像幅より大きい場合がある（アライメントのため）
- 正しいインデックス計算が重要

### 2. 非同期処理とデータの一貫性
- プレビューと保存で同じデータソースを使用することの重要性
- キャッシュされたデータの適切な管理

### 3. デバッグの重要性
- 段階的な問題の切り分け
- 仮説の検証と修正の繰り返し

## 今後の改善提案

1. **エラーハンドリングの強化**
   - 深度値の妥当性チェックの拡充
   - 保存失敗時のリトライ機構

2. **パフォーマンスの最適化**
   - 不要な深度推定の実行を避ける
   - メモリ使用量の最適化

3. **ユーザーエクスペリエンスの向上**
   - 保存形式の選択UI
   - 保存成功/失敗の詳細なフィードバック

4. **コードの整理**
   - 深度マップ処理を専用クラスに分離
   - テストの追加

## まとめ

今回の問題は、一見複雑に見えましたが、根本原因は「プレビューと保存で異なるデータを使用していた」というシンプルなものでした。この経験から、以下の教訓を得ました：

1. **データの一貫性**を常に意識する
2. **問題の切り分け**を段階的に行う
3. **デバッグログ**は問題解決の強力なツール
4. **シンプルな解決策**を最初に検討する

この問題解決により、PromptDAを使用した深度推定機能が安定して動作するようになりました。