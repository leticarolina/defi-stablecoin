export function Card({ title, color, children }) {
    const colorClasses = {
        blue: "from-blue-50 via-indigo-100 to-blue-200 border-blue-200",
        red: "from-rose-50 via-rose-100 to-red-200 border-rose-200",
        green: "from-green-50 via-green-100 to-emerald-200 border-green-200",
        indigo: "from-white to-indigo-100 border-indigo-200",
    };

    const textColor =
        color === "blue"
            ? "text-blue-800"
            : color === "red"
                ? "text-red-800"
                : color === "green"
                    ? "text-green-800"
                    : "text-indigo-800";

    return (
        // <div className={`p-6 bg-gradient-to-br rounded-2xl shadow-md hover:shadow-lg transition-shadow ${colorClasses[color]} border`}>
        <div
            className={`flex flex-col justify-between p-6 bg-gradient-to-br rounded-2xl shadow-md hover:shadow-lg transition-shadow ${colorClasses[color]} border h-full`}
            style={{ minHeight: "260px" }}
        >
            <h2 className={`text-lg font-semibold mb-2 flex items-center gap-2 ${textColor}`}>{title}</h2>
            {children}
        </div >
    );
}
