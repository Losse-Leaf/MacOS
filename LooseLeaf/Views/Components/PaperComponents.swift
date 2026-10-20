// PaperComponents.swift
// 纸本通用组件集 (Paper Components) —— 拆分后的索引文件
//
// 职责说明：
//   本文件原先把 20 个互不相关的纸本控件堆叠在一起，导致 Swift 增量编译变慢、
//   代码评审困难。现已按职责域拆分到同目录下的独立文件，逻辑与公开 API 保持不变：
//
//   - PaperHeatmap.swift          岁月留白刻度切线、生活刻度热力图
//   - PaperButtons.swift          胶囊按钮、悬停修饰符、主按钮样式、焦点环
//   - PaperDateTimePicker.swift   快捷时刻真源、日期选择器、时刻选择器、时空组合选择器
//   - PaperCityPicker.swift       省市行政区划点选器
//   - PaperSelect.swift           纸本拟物下拉单选器与选项模型
//   - PaperSegmentedControl.swift 纸本分段切换器与分段项模型
//   - PaperToggles.swift          纸本复选框与滑动开关样式
//   - PaperElevation.swift        纸张物理微投影修饰符
//
//   拆分后本文件不再保留任何类型声明，仅作组件索引与变更说明之用。
//   若后续需要新增纸本通用控件，请按职责归入上述对应文件，避免重新堆叠。
