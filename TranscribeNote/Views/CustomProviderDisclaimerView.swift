import SwiftUI

/// Disclaimer shown once when a user in the China storefront selects the Custom provider,
/// reminding them that the endpoint they connect to must comply with local regulations.
struct CustomProviderDisclaimerView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("合规提醒")
                .font(DS.Typography.title)
                .bold()

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("自定义端点要求使用已备案或合法合规的 AI 服务。请确认：")
                    .font(DS.Typography.sectionHeader)

                bulletItem("所连接的 AI 服务已完成国内算法备案，或属于合法合规的本地部署")
                bulletItem("数据传输和存储符合《个人信息保护法》等相关法律法规")

                Text("本应用仅提供接口调用功能，不对用户所连接的第三方服务的合规性承担任何责任。因使用不合规服务产生的一切法律后果由用户自行承担。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, DS.Spacing.xs)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

            Button("我已知晓") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(DS.Spacing.xxl)
        .frame(width: 420)
    }

    private func bulletItem(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Circle()
                .fill(.secondary)
                .frame(width: 4, height: 4)
            Text(text)
                .font(DS.Typography.body)
        }
    }
}
