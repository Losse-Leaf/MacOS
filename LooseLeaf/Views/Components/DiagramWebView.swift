// DiagramWebView.swift
// LooseLeaf · 架构与数据图表 WebKit 渲染容器 (WebKit Diagram Bridge)
// 遵循 diagram-design 技能规范与 docs/macos.md 原生设计契约：
// 支持渲染基于 ECharts / D3 / SVG 的日历图与事件树图，纸墨大地色盘与深浅色模式自适应。

import SwiftUI
import WebKit
import AppKit

/// 基于 WKWebView 的图表视图桥接 (DiagramWebView)
public struct DiagramWebView: NSViewRepresentable {
    public let htmlContent: String
    public var onSelectDate: ((String) -> Void)?
    public var onSelectEntry: ((Int) -> Void)?

    public init(
        htmlContent: String,
        onSelectDate: ((String) -> Void)? = nil,
        onSelectEntry: ((Int) -> Void)? = nil
    ) {
        self.htmlContent = htmlContent
        self.onSelectDate = onSelectDate
        self.onSelectEntry = onSelectEntry
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // 注入与原生 Swift 通信的脚本桥接
        contentController.add(context.coordinator, name: "diagramBridge")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // 透明背景，露出纸张微噪点
        webView.navigationDelegate = context.coordinator

        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // 当 HTML 内容发生实质变更时重新加载
        if context.coordinator.lastHTML != htmlContent {
            context.coordinator.lastHTML = htmlContent
            nsView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }

    public static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "diagramBridge")
        nsView.navigationDelegate = nil
    }

    public final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: DiagramWebView
        var lastHTML: String = ""

        init(_ parent: DiagramWebView) {
            self.parent = parent
            self.lastHTML = parent.htmlContent
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "diagramBridge",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            Task { @MainActor in
                if type == "selectDate", let dateStr = body["date"] as? String {
                    self.parent.onSelectDate?(dateStr)
                } else if type == "selectEntry", let entryId = body["id"] as? Int {
                    self.parent.onSelectEntry?(entryId)
                }
            }
        }
    }
}

/// 图表 HTML 生成器 (遵循 diagram-design 技能 Editorial 纸墨规范)
public enum DiagramHTMLBuilder {

    /// 生成 ECharts / SVG 日历图 HTML
    public static func buildCalendarChartHTML(
        year: Int,
        entryCounts: [String: Int],
        isDark: Bool
    ) -> String {
        let paper = isDark ? "#2d3142" : "#f5f5f5"
        let paper2 = isDark ? "#393e53" : "#ececec"
        let ink = isDark ? "#f5f5f5" : "#2d3142"
        let inkMuted = isDark ? "#bfc0c0" : "#4f5d75"
        let _ = isDark ? "#f08a59" : "#bf4520"
        let accentMoss = isDark ? "#8cb369" : "#5b7050"

        // 构造数据序列 [[ "YYYY-MM-DD", count ], ...]
        var dataEntries: [String] = []
        for (dateKey, count) in entryCounts where dateKey.hasPrefix("\(year)") {
            dataEntries.append("[\"\(dateKey)\", \(count)]")
        }
        let dataJSON = "[\n" + dataEntries.joined(separator: ",\n") + "\n]"

        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>生活刻度 · 时光日历图</title>
          <script src="https://cdn.jsdelivr.net/npm/echarts@5/dist/echarts.min.js"></script>
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body {
              width: 100%; height: 100%;
              background: transparent;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, serif;
              overflow: hidden;
            }
            #chart-container {
              width: 100%;
              height: 100%;
              min-height: 240px;
            }
            .fallback-notice {
              display: none;
              padding: 20px;
              color: \(inkMuted);
              font-size: 13px;
              text-align: center;
            }
          </style>
        </head>
        <body>
          <div id="chart-container"></div>
          <div id="fallback" class="fallback-notice">正在载入或请使用本地原生月历模式…</div>
          <script>
            function notifyDate(dateStr) {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.diagramBridge) {
                window.webkit.messageHandlers.diagramBridge.postMessage({ type: 'selectDate', date: dateStr });
              }
            }

            try {
              if (typeof echarts === 'undefined') {
                document.getElementById('fallback').style.display = 'block';
              } else {
                var chartDom = document.getElementById('chart-container');
                var myChart = echarts.init(chartDom, null, { renderer: 'svg' });
                var data = \(dataJSON);

                var option = {
                  backgroundColor: 'transparent',
                  tooltip: {
                    position: 'top',
                    backgroundColor: '\(paper2)',
                    borderColor: '\(accentMoss)',
                    textStyle: { color: '\(ink)', fontSize: 12 },
                    formatter: function (p) {
                      var d = p.data[0];
                      var v = p.data[1];
                      return d + ' · ' + v + ' 篇手稿留痕 (点击筛选)';
                    }
                  },
                  visualMap: {
                    min: 0,
                    max: 5,
                    calculable: false,
                    orient: 'horizontal',
                    left: 'center',
                    bottom: 8,
                    itemWidth: 12,
                    itemHeight: 12,
                    text: ['笔墨丰盛', '岁月留白'],
                    textStyle: { color: '\(inkMuted)', fontSize: 11 },
                    inRange: {
                      color: [
                        '\(isDark ? "rgba(245,245,245,0.06)" : "rgba(45,49,66,0.06)")',
                        '\(accentMoss)44',
                        '\(accentMoss)88',
                        '\(accentMoss)'
                      ]
                    }
                  },
                  calendar: {
                    top: 30,
                    left: 48,
                    right: 32,
                    bottom: 46,
                    cellSize: ['auto', 14],
                    range: '\(year)',
                    splitLine: {
                      show: true,
                      lineStyle: { color: '\(isDark ? "rgba(245,245,245,0.12)" : "rgba(45,49,66,0.12)")', width: 1 }
                    },
                    itemStyle: {
                      color: '\(paper)',
                      borderWidth: 0.5,
                      borderColor: '\(isDark ? "rgba(245,245,245,0.15)" : "rgba(45,49,66,0.15)")'
                    },
                    yearLabel: { show: false },
                    monthLabel: {
                      nameMap: 'cn',
                      color: '\(inkMuted)',
                      fontSize: 11
                    },
                    dayLabel: {
                      firstDay: 1,
                      nameMap: ['日', '一', '', '三', '', '五', ''],
                      color: '\(inkMuted)',
                      fontSize: 10
                    }
                  },
                  series: [{
                    type: 'heatmap',
                    coordinateSystem: 'calendar',
                    data: data
                  }]
                };

                myChart.setOption(option);
                myChart.on('click', function(params) {
                  if (params.data && params.data[0]) {
                    notifyDate(params.data[0]);
                  }
                });

                window.addEventListener('resize', function() {
                  myChart.resize();
                });
              }
            } catch(e) {
              console.error(e);
              document.getElementById('fallback').style.display = 'block';
            }
          </script>
        </body>
        </html>
        """
    }

    /// 生成 ECharts / SVG 事件树图 HTML (严格遵循 diagram-design type-tree 树图规范)
    public static func buildEventTreeChartHTML(
        categories: [String: [(id: Int, title: String, date: String, type: String)]],
        isDark: Bool
    ) -> String {
        let paper = isDark ? "#2d3142" : "#f5f5f5"
        let paper2 = isDark ? "#393e53" : "#ececec"
        let ink = isDark ? "#f5f5f5" : "#2d3142"
        let inkMuted = isDark ? "#bfc0c0" : "#4f5d75"
        let accent = isDark ? "#f08a59" : "#bf4520"

        // 构造 Tree 数据结构: 根节点 -> 分类分支 -> 事件叶子节点
        var categoryNodes: [String] = []
        for (catName, entries) in categories {
            var leafNodes: [String] = []
            for item in entries.prefix(12) {
                let cleanTitle = item.title.replacingOccurrences(of: "\"", with: "\\\"")
                leafNodes.append("""
                {
                  "name": "\(cleanTitle)",
                  "value": "\(item.date)",
                  "entryId": \(item.id),
                  "itemStyle": { "borderColor": "\(accent)" }
                }
                """)
            }
            categoryNodes.append("""
            {
              "name": "\(catName) (\(entries.count))",
              "children": [ \(leafNodes.joined(separator: ", ")) ]
            }
            """)
        }

        let treeDataJSON = """
        {
          "name": "《散页》生活卷宗",
          "children": [ \(categoryNodes.joined(separator: ", ")) ]
        }
        """

        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>时间流 · 事件树图</title>
          <script src="https://cdn.jsdelivr.net/npm/echarts@5/dist/echarts.min.js"></script>
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body {
              width: 100%; height: 100%;
              background: transparent;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, serif;
              overflow: hidden;
            }
            #chart-container {
              width: 100%;
              height: 100%;
              min-height: 480px;
            }
          </style>
        </head>
        <body>
          <div id="chart-container"></div>
          <script>
            function notifyEntry(id) {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.diagramBridge) {
                window.webkit.messageHandlers.diagramBridge.postMessage({ type: 'selectEntry', id: id });
              }
            }

            try {
              var chartDom = document.getElementById('chart-container');
              var myChart = echarts.init(chartDom, null, { renderer: 'svg' });
              var treeData = \(treeDataJSON);

              var option = {
                backgroundColor: 'transparent',
                tooltip: {
                  trigger: 'item',
                  triggerOn: 'mousemove',
                  backgroundColor: '\(paper2)',
                  borderColor: '\(accent)',
                  textStyle: { color: '\(ink)', fontSize: 12 },
                  formatter: function(p) {
                    if (p.data.value) {
                      return '<b>' + p.data.name + '</b><br/>发生时刻：' + p.data.value + '<br/>(点击打开详情)';
                    }
                    return p.data.name;
                  }
                },
                series: [
                  {
                    type: 'tree',
                    data: [treeData],
                    top: '6%',
                    left: '12%',
                    bottom: '6%',
                    right: '24%',
                    symbolSize: 8,
                    edgeShape: 'polyline', // 直角拐角连接线 (Orthogonal connectors 严格对标 diagram-design 规范)
                    lineStyle: {
                      color: '\(inkMuted)',
                      width: 1.2,
                      curveness: 0
                    },
                    itemStyle: {
                      color: '\(paper)',
                      borderColor: '\(accent)',
                      borderWidth: 1.5
                    },
                    label: {
                      position: 'left',
                      verticalAlign: 'middle',
                      align: 'right',
                      fontSize: 12,
                      color: '\(ink)'
                    },
                    leaves: {
                      label: {
                        position: 'right',
                        verticalAlign: 'middle',
                        align: 'left',
                        fontSize: 11,
                        color: '\(ink)'
                      }
                    },
                    emphasis: {
                      focus: 'descendant'
                    },
                    expandAndCollapse: true,
                    animationDuration: 400
                  }
                ]
              };

              myChart.setOption(option);
              myChart.on('click', function(params) {
                if (params.data && params.data.entryId) {
                  notifyEntry(params.data.entryId);
                }
              });

              window.addEventListener('resize', function() {
                myChart.resize();
              });
            } catch(e) {
              console.error(e);
            }
          </script>
        </body>
        </html>
        """
    }
}
