
@Entry
@Component
struct Index {
  build() {
    // 空白页面，实际内容由路由控制
    Column() {
      Text('欢迎使用音乐标签编辑器')
        .fontSize(20)
        .fontColor('#3F51B5')
        .fontWeight(FontWeight.Bold)
      
      Text('请点击下方按钮跳转到主页面')
        .fontSize(14)
        .fontColor('#666666')
        .margin({ top: 10 })
      
      Button('进入编辑器')
        .width(160)
        .height(44)
        .fontSize(16)
        .backgroundColor('#3F51B5')
        .fontColor('#FFFFFF')
        .borderRadius(22)
        .margin({ top: 30 })
        .onClick(() => {
          try {
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/AudioTagEditorPage'
            }).then(() => {
              console.log('页面跳转成功');
            }).catch((error: Error) => {
              console.error('页面跳转失败:', error.message);
            });
          } catch (error) {
            console.error('路由跳转异常:', error);
          }
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}