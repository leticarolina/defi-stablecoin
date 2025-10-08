export function InputField({ onChange, stateValue, type, placeholder }) {
    const colorClasses = {
        blue: "border-blue-200 focus:ring-blue-400",
        red: "border-rose-200 focus:ring-red-400",
        green: "border-green-200 focus:ring-green-400",
        indigo: "border-indigo-200 focus:ring-indigo-400",
    };
    return (
        <input
            type={type}
            placeholder={placeholder}
            className={`border ${colorClasses[color]} p-2 rounded-md focus:ring-2 outline-none`}
            value={stateValue}
            onChange={(e) => onChange(e.target.value)
            } // just passes value up
        />
    )
}